require("deepcore/std/class")

local SCALE = 30
local DEFAULT_CAP = 300
local FIRST_ARRIVAL = 15

local ok_data, DATA = pcall(require, "eawx-plugins-gamescoring/diplomacy-reinforcements/ReinforcementsData")
local POPULATION = ok_data and DATA.POPULATION or {}
local CAPS = ok_data and DATA.CAP or {}
local STRUCTURES = ok_data and DATA.STRUCTURES or {}
local INTERDICTORS = ok_data and DATA.INTERDICTORS or {}
local HOLD_SECONDS = 0.5
local LAND_DELAY = 3
local BORDER_DELAY = 90
local RETREAT_AFTER = 20
local RETREAT_RATIO = 1.2
local RESOLVE_LOSS = 0.5
local START_SETTLE = 8
local KILL_WAIT = 3
local RETREAT_COUNTDOWN = 10
local GONE = {}

local function log(text)
    if Engine_Log then
        Engine_Log("REINFORCEMENTS " .. text)
    end
end

local function M_min(a, b)
    return (a < b) and a or b
end

local function math_floor_half(n)
    local q = 0
    while n >= 2 do
        n = n - 2
        q = q + 1
    end
    return q
end

local function split(text, sep)
    local out = {}
    for part in string.gfind(text or "", "[^" .. sep .. "]+") do
        table.insert(out, part)
    end
    return out
end

local function entry_point(player)
    for _, object in pairs(Find_All_Objects_Of_Type(player) or {}) do
        if TestValid(object) then
            return object
        end
    end
    local human = Find_Player("local")
    local allies = {}
    if human and human ~= player and player.Is_Ally(human) then
        table.insert(allies, human)
    end
    for name in pairs(CAPS) do
        local other = Find_Player(name)
        if other and other ~= player and other ~= human and player.Is_Ally(other) then
            table.insert(allies, other)
        end
    end
    for _, ally in ipairs(allies) do
        for _, object in pairs(Find_All_Objects_Of_Type(ally) or {}) do
            if TestValid(object) then
                return object
            end
        end
    end
    for _, name in ipairs({"Attacker Entry Position", "Defending Forces Position"}) do
        local ok, points = pcall(Find_All_Objects_Of_Type, name)
        for _, point in pairs(ok and points or {}) do
            if TestValid(point) then
                return point
            end
        end
    end
    return nil
end

local function population(player)
    local total = 0
    for _, object in pairs(Find_All_Objects_Of_Type(player) or {}) do
        if TestValid(object) then
            total = total + (POPULATION[object.Get_Type().Get_Name()] or 0)
        end
    end
    return total, CAPS[string.upper(player.Get_Faction_Name())] or DEFAULT_CAP
end

local function neighbours(planet)
    local ok, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
    local ok_n, names = false, nil
    if ok and Trade.neighbours then
        ok_n, names = pcall(Trade.neighbours, nil, planet)
    end
    local list = {}
    for _, name in ipairs(ok_n and names or {}) do
        local there = FindPlanet(name)
        if there then
            table.insert(list, there)
        end
    end
    return list
end

local function lose_copies(fleet)
    local player = Find_Player(fleet.owner)
    local planet = player and Engine_Battle_Planet and FindPlanet(Engine_Battle_Planet() or "")
    local dead = {}
    for _, copy in ipairs(fleet.copies) do
        if not copy.alive then
            dead[string.upper(copy.name)] = (dead[string.upper(copy.name)] or 0) + 1
        end
    end
    local removed = 0
    local worlds = {fleet.origin and FindPlanet(fleet.origin) or nil, planet}
    for _, where in pairs(worlds) do
        for _, unit in pairs(where and Find_All_Objects_Of_Type(player) or {}) do
            local name = TestValid(unit) and string.upper(unit.Get_Type().Get_Name())
            local ok, parent = pcall(unit.Get_Parent_Object)
            if name and (dead[name] or 0) > 0 and ok and parent and TestValid(parent)
                and parent.Get_Type().Get_Name() == "GALACTIC_FLEET" and parent.Get_Planet_Location() == where then
                dead[name] = dead[name] - 1
                unit.Despawn()
                removed = removed + 1
            end
        end
    end
    log(fleet.owner .. ": " .. removed .. " ships lost in the battle removed from its fleet")
end

local weight

local function lose_resolved(resolution)
    local planet = Engine_Battle_Planet and FindPlanet(Engine_Battle_Planet() or "")
    if not planet then
        return
    end
    local function ships_there(player)
        local list = {}
        for _, unit in pairs(Find_All_Objects_Of_Type(player) or {}) do
            local name = TestValid(unit) and string.upper(unit.Get_Type().Get_Name())
            local ok, parent = pcall(unit.Get_Parent_Object)
            if name and (POPULATION[name] or 0) > 0 and ok and parent and TestValid(parent)
                and parent.Get_Type().Get_Name() == "GALACTIC_FLEET" and parent.Get_Planet_Location() == planet then
                table.insert(list, unit)
            end
        end
        return list
    end
    for name in pairs(resolution.losers) do
        local player = Find_Player(name)
        local list = player and ships_there(player) or {}
        for _, unit in ipairs(list) do
            pcall(unit.Despawn)
        end
        if list[1] then
            log("auto-resolve: " .. name .. " loses its " .. table.getn(list) .. " ships not in the battle")
        end
    end
    for name, owed in pairs(resolution.owed) do
        local player = Find_Player(name)
        local list = player and ships_there(player) or {}
        local paid, n = 0, 0
        while paid < owed and list[1] do
            local unit = table.remove(list, GameRandom.Free_Random(1, table.getn(list)))
            paid, n = paid + weight(unit), n + 1
            pcall(unit.Despawn)
        end
        if n > 0 then
            log("auto-resolve: " .. name .. " loses " .. n .. " ships not in the battle (" .. paid .. " of " .. owed .. ")")
        end
    end
end

local function world_label(key)
    local name = GlobalValue.Get("DP_WORLD_" .. key)
    if type(name) == "string" and name ~= "" then
        return name
    end
    local text = string.gsub(string.lower(key), "_", " ")
    return (string.gsub(text, "(%a)(%w*)", function(a, b) return string.upper(a) .. b end))
end

local function send_home(list)
    local planet = Engine_Battle_Planet and FindPlanet(Engine_Battle_Planet() or "")
    if not planet then
        return
    end
    local by_owner = {}
    for _, f in ipairs(list) do
        by_owner[f.owner] = by_owner[f.owner] or {origins = {}, all = {}, n = 0}
        local o = by_owner[f.owner]
        o.origins[f.origin] = o.origins[f.origin] or {count = {}, n = 0}
        for _, name in ipairs(split(f.types, ",")) do
            name = string.upper(name)
            o.origins[f.origin].count[name] = (o.origins[f.origin].count[name] or 0) + 1
            o.origins[f.origin].n = o.origins[f.origin].n + 1
            o.all[name] = (o.all[name] or 0) + 1
            o.n = o.n + 1
        end
    end
    local function same(count, n, want, wanted)
        if n ~= wanted then
            return false
        end
        for name, k in pairs(want) do
            if count[name] ~= k then
                return false
            end
        end
        return true
    end
    for owner, o in pairs(by_owner) do
        local player = Find_Player(owner)
        local fleets = {}
        for _, unit in pairs(player and Find_All_Objects_Of_Type(player) or {}) do
            local ok, fleet = pcall(unit.Get_Parent_Object)
            if ok and fleet and TestValid(fleet) and fleet.Get_Type().Get_Name() == "GALACTIC_FLEET"
                and fleet.Get_Planet_Location() == planet then
                local entry
                for _, f in ipairs(fleets) do
                    if f.fleet == fleet then
                        entry = f
                        break
                    end
                end
                if not entry then
                    entry = {fleet = fleet, count = {}, n = 0}
                    table.insert(fleets, entry)
                end
                local name = string.upper(unit.Get_Type().Get_Name())
                entry.count[name] = (entry.count[name] or 0) + 1
                entry.n = entry.n + 1
            end
        end
        local most, most_n = nil, -1
        for origin, g in pairs(o.origins) do
            if g.n > most_n then
                most, most_n = origin, g.n
            end
        end
        for _, f in ipairs(fleets) do
            local home
            for origin, g in pairs(o.origins) do
                if same(f.count, f.n, g.count, g.n) then
                    home = origin
                end
            end
            if not home and same(f.count, f.n, o.all, o.n) then
                home = most
            end
            local there = home and FindPlanet(home)
            if there and Engine_Safe_Path then
                local ok_p, path = pcall(Engine_Safe_Path, owner, Engine_Battle_Planet() or "", home)
                local first = ok_p and type(path) == "string" and (string.gsub(path, ";.*$", "")) or ""
                there = first ~= "" and FindPlanet(first) or nil
                if not there then
                    log(owner .. " fleet has no safe way home to " .. home .. ": it stays")
                end
            end
            if there then
                pcall(f.fleet.Move_To, there)
                log(owner .. " fleet flies home to " .. home)
            end
        end
    end
end

local function retreat(player)
    local planet = player and Engine_Battle_Planet and FindPlanet(Engine_Battle_Planet() or "")
    if not planet then
        return
    end
    local best, fallback
    for _, there in ipairs(neighbours(planet)) do
        local owner = there.Get_Owner()
        if owner == player or player.Is_Ally(owner) then
            best = best or there
        elseif not owner.Is_Enemy(player) then
            fallback = fallback or there
        end
    end
    if not best and not fallback then
        local ok, all = pcall(FindPlanet.Get_All_Planets)
        local nearest
        for _, there in pairs(ok and all or {}) do
            local owner = there.Get_Owner()
            if there ~= planet and (owner == player or player.Is_Ally(owner)) then
                local d = planet.Get_Distance(there)
                if not nearest or d < nearest then
                    best, nearest = there, d
                end
            end
        end
    end
    local target = best or fallback
    if not target then
        log("no world to retreat to for " .. player.Get_Faction_Name())
        return
    end
    local sent = {}
    for _, unit in pairs(Find_All_Objects_Of_Type(player) or {}) do
        local ok, fleet = pcall(unit.Get_Parent_Object)
        if ok and fleet and TestValid(fleet) and fleet.Get_Type().Get_Name() == "GALACTIC_FLEET"
            and not sent[tostring(fleet)] and fleet.Get_Planet_Location() == planet then
            sent[tostring(fleet)] = true
            pcall(fleet.Move_To, target)
        end
    end
    log(player.Get_Faction_Name() .. " retreats to " .. target.Get_Type().Get_Name())
end

local function centre(players)
    local x, y, z, n = 0, 0, 0, 0
    for _, player in ipairs(players) do
        for _, object in pairs(Find_All_Objects_Of_Type(player) or {}) do
            local ok, a, b, c = pcall(function() return object.Get_Position().Get_XYZ() end)
            if ok and a and TestValid(object) then
                x, y, z, n = x + a, y + b, z + c, n + 1
            end
        end
    end
    if n == 0 then
        return nil
    end
    return x / n, y / n, z / n
end

local function sides(except)
    local human = Find_Player("local")
    local friends, foes = {human}, {}
    for name in pairs(CAPS) do
        local other = Find_Player(name)
        if other and other ~= human and other ~= except then
            if other.Is_Ally(human) then
                table.insert(friends, other)
            elseif other.Is_Enemy(human) then
                table.insert(foes, other)
            end
        end
    end
    return friends, foes
end

local function third_point(player, team)
    local friends, foes = sides(player)
    local ax, ay, az = centre(friends)
    local bx, by, bz = centre(foes)
    if not ax or not bx then
        return nil
    end
    local side = (team - 2 * math_floor_half(team) == 1) and 0.5 or -0.5
    local x, y = (ax + bx) / 2 - (by - ay) * side, (ay + by) / 2 + (bx - ax) * side
    local ok, position = pcall(Create_Position, x, y, (az + bz) / 2)
    return ok and position or nil, x, y
end

local function forces()
    local human = Find_Player("local")
    local mine, allied, hostile, allies, foes = 0, 0, 0, 0, 0
    local interdicting = {}
    for name in pairs(CAPS) do
        local player = not GONE[string.upper(name)] and Find_Player(name)
        if player then
            local n = 0
            for _, object in pairs(Find_All_Objects_Of_Type(player) or {}) do
                if TestValid(object) then
                    local type_name = object.Get_Type().Get_Name()
                    if (POPULATION[type_name] or 0) > 0 or STRUCTURES[type_name] then
                        n = n + 1
                    end
                    if INTERDICTORS[type_name] and not interdicting[name] then
                        local ok, on = pcall(object.Is_Ability_Active, "INTERDICT")
                        if ok and on then
                            interdicting[name] = player
                        end
                    end
                end
            end
            if n > 0 then
                if player == human then
                    mine = n
                elseif player.Is_Ally(human) then
                    allied, allies = allied + n, allies + 1
                elseif player.Is_Enemy(human) then
                    hostile, foes = hostile + n, foes + 1
                end
            end
        end
    end
    return mine, allied, hostile, allies, foes, interdicting
end

local BANNER_ROWS = 4
local BANNER_SECONDS = 0.25
local shown_now, text_now, icon_now, colour_now = {}, {}, {}, {}

local function show(name, visible)
    if shown_now[name] ~= visible then
        shown_now[name] = visible
        pcall(GUI_Component_Visibility, name, visible)
    end
end

local function text(name, value)
    if text_now[name] ~= value then
        text_now[name] = value
        pcall(GUI_Component_Text, name, value)
    end
end

local function icon(name, texture)
    if icon_now[name] ~= texture then
        icon_now[name] = texture
        pcall(GUI_Button_Icon, name, texture, 1, 1, 1, 1)
        pcall(GUI_Component_Enable, name, true)
    end
end

local PALE, HELD = {0.84, 0.86, 0.9}, {1, 0.66, 0.24}
local OURS, THEIRS = {0.6, 0.86, 0.6}, {0.92, 0.55, 0.51}
local THIRD_COLOURS = {{1, 0.62, 0.2}, {0.95, 0.85, 0.3}, {0.78, 0.6, 1}, {0.45, 0.82, 0.9}}

local function colour(name, rgb)
    if colour_now[name] ~= rgb then
        colour_now[name] = rgb
        pcall(GUI_Text_Color, name, rgb[1], rgb[2], rgb[3], 1)
    end
end

local function clock(seconds)
    if seconds < 0 then
        seconds = 0
    end
    local m = tonumber(string.format("%d", seconds / 60))
    local s = tonumber(string.format("%d", seconds - m * 60))
    return m .. ":" .. ((s < 10) and "0" or "") .. s
end

local function label(owner)
    local name = GlobalValue.Get("DP_NAME_" .. owner)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return (string.gsub(string.lower(owner), "_", " "))
end

local function emblem(owner)
    local texture = GlobalValue.Get("DP_EMBLEM_" .. owner)
    if type(texture) == "string" and texture ~= "" then
        return texture
    end
    return "dp_emblem_" .. string.lower(owner) .. ".tga"
end

local function hide_banner()
    show("dp_rt_shell", false)
end

Reinforcements = class()

function Reinforcements:new()
    self.fleets = nil
end

function Reinforcements:update()
    local mode = Get_Game_Mode()
    if mode == "Galactic" then
        if self.fleets and Engine_Inbound_Settle then
            local go_on = GlobalValue.Get("DP_BATTLE_CONTINUE")
            go_on = type(go_on) == "string" and go_on ~= ""
            local ok, settled = pcall(Engine_Inbound_Settle, go_on and 1 or 0)
            for _, fleet in ipairs(self.fleets) do
                if fleet.copies then
                    pcall(lose_copies, fleet)
                end
            end
            if self.resolution then
                pcall(lose_resolved, self.resolution)
            end
            local retreated, home = {}, {}
            for _, line in ipairs(ok and split(settled, "\n") or {}) do
                local _, _, owner, how, origin, types = string.find(line, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
                if not owner then
                    _, _, owner, how = string.find(line, "^([^|]*)|(.*)$")
                end
                log("after the battle: " .. tostring(owner) .. " " .. tostring(how) .. " " .. tostring(origin))
                if origin and origin ~= "" then
                    table.insert(home, {owner = owner, origin = origin, types = types})
                elseif how == "retreat" and owner and not retreated[owner]
                    and (not go_on or Find_Player(owner) == Find_Player("local")) then
                    retreated[owner] = true
                    pcall(retreat, Find_Player(owner))
                end
            end
            pcall(send_home, home)
            if go_on and Engine_Battle_Continue then
                GlobalValue.Set("DP_BATTLE_CONTINUE", "")
                local ok_c, who = pcall(Engine_Battle_Continue)
                log("the battle goes on without the player: " .. tostring(ok_c and who))
            end
        end
        if Engine_Autoresolve_Own then
            pcall(Engine_Autoresolve_Own, 0)
        end
        if self.fleets then
            hide_banner()
            show("dp_rt_q_shell", false)
        end
        self.fleets = nil
        self.ground = nil
        self.teams_seen, self.resolved, self.gone, self.had_mine, self.resolve_own, self.land_mode = nil, nil, nil, nil,
            nil, nil
        self.end_checked, self.end_tries, self.finishing, self.resolution = nil, nil, nil, nil
        if Engine_Fleet_Sample then
            pcall(Engine_Fleet_Sample, GetCurrentTime())
        end
        return
    end
    if mode == "Land" then
        pcall(self.land, self)
        local ok, err = pcall(self.land_tick, self)
        if not ok and not self.tick_error then
            self.tick_error = true
            log("error: " .. tostring(err))
        end
        return
    end
    if mode ~= "Space" or not Engine_Inbound then
        return
    end
    if not self.fleets then
        local ok, err = pcall(self.start, self)
        if not ok then
            log("error at the battle's start: " .. tostring(err))
            self.fleets = self.fleets or {}
        end
    end
    local ok, err = pcall(self.tick, self)
    if not ok and not self.tick_error then
        self.tick_error = true
        log("error: " .. tostring(err))
    end
end

function Reinforcements:land()
    local now = GetCurrentTime()
    if not self.ground then
        self.ground = {at = now + LAND_DELAY}
    end
    if self.ground.done or now < self.ground.at or not Engine_Battle_Allies then
        return
    end
    self.ground.done = true
    local ok, rebellion = pcall(require, "eawx-plugins/diplomacy/DiplomacyRebellionData")
    local markers = ok and rebellion.MARKERS or {}
    local neutral = Find_Player("Neutral")
    pcall(self.joint_army, self, markers, neutral)
    for _, line in ipairs(split(Engine_Battle_Allies(), "\n")) do
        local _, _, ally_name, side_name = string.find(line, "^([^|]*)|(.*)$")
        local ally, side = Find_Player(ally_name or ""), Find_Player(side_name or "")
        local types = split(Engine_Pool_Types and Engine_Pool_Types(ally_name) or "", ",")
        if ally and side and types[1] then
            local free, own = {}, nil
            for _, marker in ipairs(markers) do
                for _, point in pairs(Find_All_Objects_Of_Type(marker) or {}) do
                    if TestValid(point) then
                        if point.Get_Owner() == neutral then
                            table.insert(free, point)
                        elseif point.Get_Owner() == side and not own then
                            own = point
                        end
                    end
                end
            end
            local where = own
            if free[1] then
                where = free[GameRandom.Free_Random(1, table.getn(free))]
                pcall(where.Change_Owner, ally)
            end
            local landed = 0
            for _, name in ipairs(where and types or {}) do
                local unit_type = Find_Object_Type(name)
                if unit_type and pcall(Spawn_From_Reinforcement_Pool, unit_type, where, ally) then
                    landed = landed + 1
                end
            end
            log(ally_name .. " lands with " .. side_name .. ": " .. landed .. " of " .. table.getn(types)
                .. (free[1] and " at a neutral point it took" or " at its side's landing point"))
        end
    end
end

function Reinforcements:joint_army(markers, neutral)
    local army = GlobalValue.Get("DP_JOINT_ARMY")
    local planet = Engine_Battle_Planet and Engine_Battle_Planet()
    if type(army) ~= "string" or army == "" or not planet then
        return
    end
    local _, _, target, ally_name, list = string.find(army, "^([^|]*)|([^|]*)|(.*)$")
    local ally, human = Find_Player(ally_name or ""), Find_Player("local")
    if not ally or string.upper(planet) ~= target then
        return
    end
    local free, own = {}, nil
    for _, marker in ipairs(markers) do
        for _, point in pairs(Find_All_Objects_Of_Type(marker) or {}) do
            if TestValid(point) then
                if point.Get_Owner() == neutral then
                    table.insert(free, point)
                elseif point.Get_Owner() == human and not own then
                    own = point
                end
            end
        end
    end
    local where = own
    if free[1] then
        where = free[GameRandom.Free_Random(1, table.getn(free))]
        pcall(where.Change_Owner, ally)
    end
    if not where then
        return
    end
    pcall(ally.Enable_As_Actor)
    local landed = 0
    for _, name in ipairs(split(list, ",")) do
        local unit_type = Find_Object_Type(name)
        if unit_type and pcall(Spawn_Unit, unit_type, where, ally) then
            landed = landed + 1
        end
    end
    GlobalValue.Set("DP_JOINT_ARMY_LANDED", target)
    log("joint invasion: " .. ally_name .. " lands " .. landed .. " companies at " .. target)
end

function Reinforcements:start()
    self.fleets = {}
    GONE = {}
    shown_now, text_now, icon_now, colour_now = {}, {}, {}, {}
    self.countdowns_shown = nil
    self.engine_retreats, self.human_retreating, self.won_tries, self.next_win = {}, false, 0, 0
    self.no_actor = {}
    self.teams_seen, self.holding, self.next_count, self.teams, self.lanes = false, false, 0, 0, {}
    self.interdicting, self.last_tick = {}, nil
    self.present, self.third_colour, self.thirds = {}, {}, 0
    for name in pairs(CAPS) do
        local player = Find_Player(name)
        for _, object in pairs(player and Find_All_Objects_Of_Type(player) or {}) do
            if TestValid(object) then
                self.present[string.upper(name)] = true
                break
            end
        end
    end
    local friends, foes = sides(nil)
    local ax, ay = centre(friends)
    local bx, by = centre(foes)
    self.face = ax and bx and {bx - ax, by - ay} or nil
    local now = GetCurrentTime()
    local human = Find_Player("local")
    local ok_l, lane_text = false, nil
    if Engine_Battle_Lane then
        ok_l, lane_text = pcall(Engine_Battle_Lane)
    end
    local _, _, human_attacks, from_world = string.find(ok_l and lane_text or "", "^[^|]*|([^|]*)|(.*)$")
    if from_world and from_world ~= "" then
        local x, y, z = centre(human_attacks == "1" and {human} or foes)
        if x then
            self.start_from = {world = from_world, human = human_attacks == "1", x = x, y = y, z = z,
                               settle_at = now + START_SETTLE}
        end
    end
    local enabled = {}
    local by_world = {}
    GlobalValue.Set("DP_BATTLE_CONTINUE", "")
    for i, line in ipairs(split(Engine_Inbound(), "\n")) do
        local _, _, owner, eta, heading, types, origin, left =
            string.find(line, "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
        if not owner then
            _, _, owner, eta, heading, types, origin = string.find(line, "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
        end
        if origin == "" then
            origin = nil
        end
        if left == "" then
            left = nil
        end
        local group = owner and ((origin and (owner .. "|" .. origin))
            or (left and (owner .. "|>" .. left .. "|" .. string.format("%d", (tonumber(heading) or 0) / 6))))
        local ships = {}
        for _, name in ipairs(split(types, ",")) do
            if (POPULATION[string.upper(name)] or 0) > 0 then
                table.insert(ships, name)
            end
        end
        local record = group and by_world[group]
        local wait = SCALE * (tonumber(eta) or 0) + (origin and BORDER_DELAY or 0)
        if wait < FIRST_ARRIVAL then
            wait = FIRST_ARRIVAL
        end
        if record and ships[1] then
            table.insert(record.indices, i)
            for _, name in ipairs(ships) do
                table.insert(record.types, name)
            end
            record.at = M_min(record.at, now + wait)
        elseif owner and ships[1] then
            local lane = owner .. "|" .. (origin or string.format("%d", (tonumber(heading) or 0) / 6))
            record = {index = i, indices = {i}, owner = owner, at = now + wait, types = ships, lane = lane,
                      heading = tonumber(heading),
                      origin = origin, left = left}
            table.insert(self.fleets, record)
            if group then
                by_world[group] = record
            end
            local player = Find_Player(owner)
            if player and player ~= human and not enabled[owner] then
                enabled[owner] = true
                local present = false
                for _, object in pairs(Find_All_Objects_Of_Type(player) or {}) do
                    if TestValid(object) then
                        present = true
                        break
                    end
                end
                if not present then
                    local ok = pcall(player.Enable_As_Actor)
                    log("enable " .. owner .. " as a battle actor: " .. tostring(ok))
                    if not ok then
                        self.no_actor[owner] = true
                    end
                end
            end
        end
    end
    for _, record in ipairs(self.fleets) do
        log(record.owner .. ": " .. table.getn(record.types) .. " ships arrive in " .. tostring(record.at - now) .. " s"
            .. ((record.origin or record.left) and (" from " .. (record.origin or record.left) .. " ("
                .. table.getn(record.indices) .. " fleets)") or ""))
    end
end

function Reinforcements:hold(now)
    if not Engine_Battle_Hold or now < (self.next_count or 0) then
        return
    end
    self.next_count = now + HOLD_SECONDS
    self:note_retreats()
    local mine, allied, hostile, allies, foes, interdicting = forces()
    self.interdicting = interdicting
    if allies > 0 or foes > 1 then
        self.teams_seen = true
    end
    if mine > 0 then
        self.had_mine = true
    end
    local human_p = Find_Player("local")
    local coming = false
    for _, fleet in ipairs(self.fleets or {}) do
        local p = not fleet.arrived and not self.no_actor[fleet.owner] and Find_Player(fleet.owner)
        if p and p.Is_Enemy(human_p) then
            coming = true
        end
    end
    if coming then
        self.teams_seen = true
    end
    local hold = self.teams_seen and (mine + allied > 0) and (hostile > 0 or coming) or false
    local retreated = Engine_Human_Retreated and Engine_Human_Retreated() == 1
    if self.had_mine and (mine == 0 or retreated) and not self.gone then
        self.gone = true
        if allied > 0 and hostile > 0 and Engine_Battle_Planet then
            GlobalValue.Set("DP_BATTLE_CONTINUE", Engine_Battle_Planet() or "")
            log("the player left; allies and enemies fight on (on the galaxy map)")
        end
        local human = Find_Player("local")
        for _, fleet in ipairs(self.fleets or {}) do
            if fleet.arrived and Find_Player(fleet.owner) == human then
                for _, index in ipairs(fleet.indices or {fleet.index}) do
                    pcall(Engine_Inbound_Retreat, index)
                end
            end
        end
    end
    if self.gone or self.resolved then
        hold = false
    end
    if self.gone and retreated and not self.end_checked and Engine_Battle_End_Check then
        local ok, won = pcall(Engine_Battle_End_Check)
        self.end_tries = (self.end_tries or 0) + 1
        if (ok and won == 1) or self.end_tries >= 10 then
            self.end_checked = true
        end
    end
    if hold ~= (self.holding or false) then
        self.holding = hold
        pcall(Engine_Battle_Hold, hold and 1 or 0)
        log("battle hold " .. tostring(hold) .. ": yours " .. mine .. ", allied " .. allied .. ", hostile " .. hostile
            .. (coming and " (more coming)" or ""))
    end
    if not hold and self.teams_seen and not self.gone and not self.resolved and hostile == 0 and not coming
        and mine + allied > 0 and Engine_Victory_Test and self.won_tries < 20 and now >= self.next_win then
        self.next_win = now + 1
        self.won_tries = self.won_tries + 1
        local ok, won = pcall(Engine_Victory_Test, string.upper(human_p.Get_Faction_Name()))
        if ok and won == 1 then
            self.won_tries = 99
        end
    end
end

function Reinforcements:tick()
    local now = GetCurrentTime()
    self:hold(now)
    local passed = now - (self.last_tick or now)
    self.last_tick = now
    if passed > 0 then
        for _, fleet in ipairs(self.fleets) do
            local player = not fleet.arrived and Find_Player(fleet.owner)
            fleet.held_now = false
            for _, interdictor in pairs(player and self.interdicting or {}) do
                if player.Is_Enemy(interdictor) then
                    fleet.at = fleet.at + passed
                    fleet.held_now = true
                    if not fleet.held then
                        fleet.held = true
                        log(fleet.owner .. " fleet held by an interdiction field")
                    end
                    break
                end
            end
        end
    end
    local fighting = false
    for _, object in pairs(Find_All_Objects_Of_Type(Find_Player("local")) or {}) do
        if TestValid(object) then
            fighting = true
            break
        end
    end
    local start = self.start_from
    if start and start.settle_at and now >= start.settle_at then
        start.settle_at = nil
        local friends, foes = sides(nil)
        local x, y, z = centre(start.human and {Find_Player("local")} or foes)
        if x then
            start.x, start.y, start.z = x, y, z
        end
    end
    pcall(self.banner, self, now)
    pcall(self.countdowns, self, now)
    pcall(self.autoresolve, self, now)
    pcall(self.finish, self, now)
    pcall(self.retreats, self, now)
    for _, fleet in ipairs(self.fleets) do
        for _, copy in ipairs(fleet.copies or {}) do
            if copy.alive and not copy.gone and not TestValid(copy.object) and fighting then
                copy.alive = false
            end
        end
        if not fleet.arrived and now >= fleet.at and not self.no_actor[fleet.owner] then
            fleet.arrived = true
            self:arrive(fleet)
        end
    end
end

function Reinforcements:banner(now)
    if now < (self.next_banner or 0) then
        return
    end
    self.next_banner = now + BANNER_SECONDS
    if now >= (self.next_icons or 0) then
        self.next_icons = now + 2
        icon_now = {}
    end
    local human = Find_Player("local")
    local sides = {l = {}, r = {}}
    for _, fleet in ipairs(self.fleets) do
        local player = Find_Player(fleet.owner)
        if player and not fleet.arrived and not self.no_actor[fleet.owner] then
            local ours = player == human or player.Is_Ally(human)
            table.insert(sides[ours and "l" or "r"], fleet)
        end
    end
    local any = sides.l[1] or sides.r[1]
    show("dp_rt_shell", any and true or false)
    if not any then
        return
    end
    for side, list in pairs(sides) do
        table.sort(list, function(a, b) return a.at < b.at end)
        for i = 1, BANNER_ROWS do
            local p = "dp_rt_" .. side .. i
            local fleet = list[i]
            for _, part in ipairs({"_bg", "_e", "_n", "_w", "_t"}) do
                show(p .. part, fleet and true or false)
            end
            if fleet then
                icon(p .. "_e", emblem(fleet.owner))
                text(p .. "_n", label(fleet.owner))
                local from = fleet.origin or fleet.left
                text(p .. "_w", from and ("from " .. world_label(from)) or "in hyperspace")
                text(p .. "_t", fleet.held_now and "HELD" or clock(fleet.at - now))
                colour(p .. "_t", fleet.held_now and HELD or PALE)
                colour(p .. "_n", self:name_colour(fleet.owner, side))
            end
        end
    end
end

function Reinforcements:name_colour(owner, side)
    if side == "l" then
        return OURS
    end
    if not self.present[owner] then
        local player = Find_Player(owner)
        local third = true
        for name in pairs(self.present) do
            local other = Find_Player(name)
            if other and player and player.Is_Ally(other) then
                third = false
            end
        end
        if third then
            if not self.third_colour[owner] then
                self.thirds = self.thirds + 1
                self.third_colour[owner] = THIRD_COLOURS[self.thirds] or THIRD_COLOURS[1]
            end
            return self.third_colour[owner]
        end
    end
    return THEIRS
end

function Reinforcements:lane_entry(heading, player)
    if not Engine_Rotate then
        return nil
    end
    local friends, foes = sides(nil)
    local fx, fy, fz = centre(friends)
    local ex, ey = centre(foes)
    if not fx or not ex then
        return nil
    end
    local mx, my = (fx + ex) / 2, (fy + ey) / 2
    local r2 = ((ex - fx) * (ex - fx) + (ey - fy) * (ey - fy)) / 4
    local r = r2
    for _ = 1, 30 do
        if r <= 0 then
            break
        end
        r = (r + r2 / r) / 2
    end
    local safe2 = 0.49 * r2
    local hostile = {}
    for name in pairs(CAPS) do
        local other = Find_Player(name)
        if other and other.Is_Enemy(player) then
            for _, object in pairs(Find_All_Objects_Of_Type(other) or {}) do
                local ok, x, y = pcall(function() return object.Get_Position().Get_XYZ() end)
                if ok and x and TestValid(object) then
                    table.insert(hostile, {x, y})
                end
            end
        end
    end
    if player.Is_Enemy(Find_Player("local")) then
        table.insert(hostile, {fx, fy})
    else
        table.insert(hostile, {ex, ey})
    end
    for _, entry in pairs(self.lanes or {}) do
        local p = entry.owner and Find_Player(entry.owner)
        if entry.x and (not p or p.Is_Enemy(player)) then
            table.insert(hostile, {entry.x, entry.y})
        end
    end
    for _, step in ipairs({0, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75, 90, -90}) do
        local tx, ty = Engine_Rotate(r, 0, heading + step)
        local px, py = mx - tx, my - ty
        local clear = true
        for _, h in ipairs(hostile) do
            local qx, qy = h[1] - px, h[2] - py
            if qx * qx + qy * qy < safe2 then
                clear = false
                break
            end
        end
        if clear then
            local ok, position = pcall(Create_Position, px, py, fz)
            log(player.Get_Faction_Name() .. " comes in from its lane's side (travelling " .. heading
                .. " degrees, turned " .. step .. ")")
            return ok and position or nil, tx, ty
        end
    end
    return nil
end

function Reinforcements:arrive(fleet)
    local player = Find_Player(fleet.owner)
    fleet.arrived_at = GetCurrentTime()
    local only = table.concat(fleet.types, ",")
    local added = 0
    for _, index in ipairs(fleet.indices or {fleet.index}) do
        local n = Engine_Inbound_Arrive(index, only)
        if n == -1 then
            added = -1
        elseif added ~= -1 then
            added = added + n
        end
    end
    local point = player and entry_point(player)
    local landed, pooled = 0, 0
    local human = Find_Player("local")
    if player and self.face and Engine_Spawn_Facing then
        local sign = (player == human or player.Is_Ally(human)) and 1 or -1
        pcall(Engine_Spawn_Facing, sign * self.face[1], sign * self.face[2])
    end
    local start = self.start_from
    local same_start = false
    if player and start and (fleet.origin or fleet.left) == start.world then
        local ours = player == human or player.Is_Ally(human)
        same_start = (start.human and ours) or (not start.human and not ours and player.Is_Enemy(human)) or false
    end
    if same_start then
        local ok, at = pcall(Create_Position, start.x, start.y, start.z)
        if ok and at then
            point = at
            log(fleet.owner .. " comes in where its side began (also from " .. start.world .. ")")
        else
            same_start = false
        end
    end
    if player and player ~= human and (player.Is_Ally(human) or player.Is_Enemy(human)) and fleet.heading
        and not same_start then
        local ok, at, fx, fy = pcall(self.lane_entry, self, fleet.heading, player)
        if ok and at then
            point = at
            if Engine_Spawn_Facing then
                pcall(Engine_Spawn_Facing, fx, fy)
            end
        end
    end
    if player and added == -1 and fleet.origin then
        fleet.copies = {}
        for _, name in ipairs(fleet.types) do
            local unit_type = Find_Object_Type(name)
            local ok, spawned = false, nil
            if unit_type and point then
                ok, spawned = pcall(Spawn_Unit, unit_type, point, player)
            end
            local object = ok and spawned and spawned[1]
            if object then
                landed = landed + 1
            end
            table.insert(fleet.copies, {name = name, object = object, alive = object ~= nil})
        end
    elseif player and added == -1 then
        self.lanes = self.lanes or {}
        local entry = self.lanes[fleet.lane]
        if same_start then
            entry = {x = start.x, y = start.y, team = 0, owner = fleet.owner}
        elseif not entry then
            self.teams = (self.teams or 0) + 1
            local position, ex, ey = third_point(player, self.teams)
            entry = {position = position, x = ex, y = ey, team = self.teams, owner = fleet.owner}
            self.lanes[fleet.lane] = entry
        end
        local position, x, y = entry.position, entry.x, entry.y
        log(fleet.owner .. " comes in at entry point " .. tostring(entry.team) .. " (lane " .. fleet.lane .. ")")
        point = position or point
        if x and Engine_Spawn_Facing and not same_start then
            pcall(Engine_Spawn_Facing, -x, -y)
        end
        fleet.copies = {}
        for _, name in ipairs(fleet.types) do
            local unit_type = Find_Object_Type(name)
            local ok, spawned = false, nil
            if unit_type and point then
                ok, spawned = pcall(Spawn_Unit, unit_type, point, player)
            end
            local object = ok and spawned and spawned[1]
            if object then
                landed = landed + 1
            end
            table.insert(fleet.copies, {name = name, object = object, alive = object ~= nil})
        end
    end
    if player and point and added > 0 then
        local used, cap = population(player)
        for _, name in ipairs(fleet.types) do
            local unit_type = Find_Object_Type(name)
            local cost = POPULATION[string.upper(name)] or 0
            if unit_type and used + cost <= cap and pcall(Spawn_From_Reinforcement_Pool, unit_type, point, player) then
                landed = landed + 1
                used = used + cost
            else
                pooled = pooled + 1
            end
        end
    end
    if Engine_Spawn_Facing then
        pcall(Engine_Spawn_Facing)
    end
    log(fleet.owner .. " fleet arrives: " .. tostring(added) .. " ships into the pool, " .. landed .. " warped in, "
        .. pooled .. " wait in the pool (" .. table.concat(fleet.types, ",") .. ")")
    if player and player ~= human and fleet.copies and not self:has_enemy(player) then
        log(fleet.owner .. " has no enemy here: it jumps away")
        self:withdraw(fleet)
    end
end

weight = function(object)
    local ok, cost = pcall(function() return object.Get_Type().Get_Build_Cost() end)
    cost = ok and tonumber(cost) or 0
    if cost > 0 then
        return cost
    end
    return 100 * (POPULATION[object.Get_Type().Get_Name()] or 1)
end

local function fights(object, land)
    if not TestValid(object) then
        return false
    end
    local name = object.Get_Type().Get_Name()
    if land then
        local ok, cost = pcall(function() return object.Get_Type().Get_Build_Cost() end)
        return ok and (tonumber(cost) or 0) > 0
    end
    if (POPULATION[name] or 0) > 0 or STRUCTURES[name] ~= nil then
        return true
    end
    return object.Is_Category("Fighter") or object.Is_Category("Bomber")
end

local function teams_now(land)
    local human = Find_Player("local")
    local teams = {}
    local ours = {powers = {}, strength = 0, friend = true, members = {}}
    table.insert(teams, ours)
    for name in pairs(CAPS) do
        local player = not GONE[string.upper(name)] and Find_Player(name)
        if player then
            local units, strength = {}, 0
            for _, object in pairs(Find_All_Objects_Of_Type(player) or {}) do
                if fights(object, land) then
                    table.insert(units, object)
                    strength = strength + weight(object)
                end
            end
            local hostile_here = player == human or player.Is_Ally(human) or player.Is_Enemy(human)
            for _, member in ipairs(ours.members) do
                hostile_here = hostile_here or player.Is_Enemy(member)
            end
            if units[1] and hostile_here and string.upper(name) ~= "NEUTRAL" then
                local power = {player = player, units = units, strength = strength}
                local team
                if player == human or player.Is_Ally(human) then
                    team = ours
                else
                    for _, t in ipairs(teams) do
                        if not t.friend then
                            for _, member in ipairs(t.members) do
                                if member.Is_Ally(player) then
                                    team = t
                                end
                            end
                        end
                    end
                    if not team then
                        team = {powers = {}, strength = 0, friend = false, members = {}}
                        table.insert(teams, team)
                    end
                end
                team.powers[string.upper(name)] = power
                team.strength = team.strength + strength
                table.insert(team.members, player)
            end
        end
    end
    return teams
end

local function hostile(a, b)
    for _, pa in ipairs(a.members) do
        for _, pb in ipairs(b.members) do
            if pa.Is_Enemy(pb) then
                return true
            end
        end
    end
    return false
end

local function team_of(teams, player)
    for _, t in ipairs(teams) do
        for _, member in ipairs(t.members) do
            if member == player then
                return t
            end
        end
    end
    return nil
end

function Reinforcements:autoresolve(now)
    if not Engine_Autoresolve_Own then
        return
    end
    local pending = false
    for _, fleet in ipairs(self.fleets or {}) do
        if not fleet.arrived then
            pending = true
        end
    end
    local own = (self.teams_seen or pending) and not self.resolved and not self.gone
    if own ~= (self.resolve_own or false) then
        self.resolve_own = own
        pcall(Engine_Autoresolve_Own, own and 1 or 0)
    end
    if not own or self.resolved or Engine_Autoresolve_Take() ~= 1 then
        return
    end
    self.resolved = true
    for _, fleet in ipairs(self.fleets or {}) do
        fleet.arrived = true
    end
    local teams = teams_now(self.land_mode)
    local best
    for _, t in ipairs(teams) do
        if t.strength > 0 and (not best or t.strength > best.strength or (t.strength == best.strength and t.friend)) then
            best = t
        end
    end
    if not best then
        best = teams[1]
    end
    local enemies = 0
    for _, t in ipairs(teams) do
        if t ~= best and hostile(t, best) then
            enemies = enemies + t.strength
        end
    end
    local loss = M_min(0.9 * best.strength, RESOLVE_LOSS * enemies)
    local summary = {}
    for _, t in ipairs(teams) do
        local names = {}
        for name in pairs(t.powers) do
            table.insert(names, name)
        end
        table.insert(summary, table.concat(names, "+") .. " " .. t.strength)
    end
    log("auto-resolve: " .. table.concat(summary, ", ") .. "; " .. (best.friend and "your side" or "the enemy")
        .. " wins, losing " .. loss)
    local kill, winners = {}, {}
    for _, t in ipairs(teams) do
        for _, power in pairs(t.powers) do
            for _, unit in ipairs(power.units) do
                table.insert((t == best) and winners or kill, unit)
            end
        end
    end
    local lost = 0
    while lost < loss and winners[1] do
        local unit = table.remove(winners, GameRandom.Free_Random(1, table.getn(winners)))
        lost = lost + weight(unit)
        table.insert(kill, unit)
    end
    for _, unit in ipairs(kill) do
        if TestValid(unit) then
            pcall(unit.Take_Damage, 100000000)
        end
    end
    local losers, owed = {}, {}
    for name in pairs(CAPS) do
        local player = Find_Player(name)
        if player and not best.powers[string.upper(name)] and string.upper(name) ~= "NEUTRAL" then
            for _, member in ipairs(best.members) do
                if player.Is_Enemy(member) then
                    losers[string.upper(name)] = true
                end
            end
        end
    end
    if lost < loss then
        local total = 0
        for _, power in pairs(best.powers) do
            total = total + power.strength
        end
        for name, power in pairs(best.powers) do
            owed[name] = (total > 0) and (loss - lost) * power.strength / total or 0
        end
    end
    self.resolution = not self.land_mode and {losers = losers, owed = owed} or nil
    self.holding = false
    self.resolve_own = false
    pcall(Engine_Battle_Hold, 0)
    local winner, most = nil, -1
    for name, power in pairs(best.powers) do
        if power.player == Find_Player("local") then
            winner, most = name, 1e30
        elseif power.strength > most then
            winner, most = name, power.strength
        end
    end
    self.finishing = winner and {name = winner, until_time = now + 20, kill = kill, since = now} or nil
end

function Reinforcements:finish(now)
    local f = self.finishing
    if not f or not Engine_Autoresolve_Finish then
        return
    end
    if not f.declared and now - f.since < KILL_WAIT then
        for _, unit in ipairs(f.kill or {}) do
            if TestValid(unit) then
                return
            end
        end
    end
    if not f.declared then
        local alive = 0
        for _, unit in ipairs(f.kill or {}) do
            if TestValid(unit) then
                alive = alive + 1
            end
        end
        log("auto-resolve: " .. (table.getn(f.kill or {}) - alive) .. " ships destroyed, " .. alive .. " still alive after "
            .. (now - f.since) .. " s")
    end
    if not f.declared and Engine_Declare_Win then
        f.declared = true
        local ok, done = pcall(Engine_Declare_Win, f.name)
        if ok and done == 1 then
            self.finishing = nil
            return
        end
    end
    if not f.pressed then
        f.pressed = now
        pcall(Engine_Autoresolve_Finish, f.name)
        return
    end
    if now - f.pressed < 3 then
        return
    end
    local ok, won = pcall(Engine_Autoresolve_Finish, f.name)
    if (ok and won == 1) or now > f.until_time then
        self.finishing = nil
    end
end

function Reinforcements:retreats(now)
    if now < (self.next_retreat or 0) then
        return
    end
    self.next_retreat = now + 1
    local teams
    for _, fleet in ipairs(self.fleets or {}) do
        local player = fleet.copies and fleet.arrived_at and not fleet.withdrawn and Find_Player(fleet.owner)
        if player and fleet.retreat_at then
            if now >= fleet.retreat_at then
                self:withdraw(fleet)
            end
        elseif player and now - fleet.arrived_at >= RETREAT_AFTER then
            teams = teams or teams_now(false)
            local mine = team_of(teams, player)
            if mine then
                local coming = 0
                for _, other in ipairs(self.fleets) do
                    local p = not other.arrived and Find_Player(other.owner)
                    if p and (p == player or p.Is_Ally(player)) then
                        for _, name in ipairs(other.types) do
                            local t = Find_Object_Type(name)
                            local ok, cost = pcall(function() return t.Get_Build_Cost() end)
                            coming = coming + ((ok and tonumber(cost)) or 100)
                        end
                    end
                end
                local own, enemy = mine.strength, 0
                for _, t in ipairs(teams) do
                    if t ~= mine and hostile(t, mine) then
                        enemy = enemy + t.strength
                    end
                end
                local held = false
                for _, interdictor in pairs(self.interdicting or {}) do
                    if player.Is_Enemy(interdictor) then
                        held = true
                    end
                end
                if not held and enemy > RETREAT_RATIO * (own + coming) then
                    for _, other in ipairs(self.fleets) do
                        if other.owner == fleet.owner and other.copies and not other.withdrawn then
                            other.retreat_at = other.retreat_at or (now + RETREAT_COUNTDOWN)
                        end
                    end
                    log(fleet.owner .. " retreats in " .. RETREAT_COUNTDOWN .. " s (hostile " .. enemy .. " against "
                        .. own .. " + " .. coming .. " coming)")
                end
            end
        end
    end
end

function Reinforcements:land_tick()
    self.land_mode = true
    if not self.ground or not self.ground.done then
        return
    end
    if self.teams_seen == nil then
        local n = 0
        for _, t in ipairs(teams_now(true)) do
            for _ in pairs(t.powers) do
                n = n + 1
            end
        end
        self.teams_seen = n > 2
        self.fleets = self.fleets or {}
    end
    pcall(self.autoresolve, self, GetCurrentTime())
    pcall(self.finish, self, GetCurrentTime())
end

function Reinforcements:on_map(player)
    for _, object in pairs(Find_All_Objects_Of_Type(player) or {}) do
        if fights(object, false) then
            return true
        end
    end
    return false
end

function Reinforcements:has_enemy(player)
    for name in pairs(CAPS) do
        local key = string.upper(name)
        local other = key ~= "NEUTRAL" and not GONE[key] and Find_Player(name)
        if other and other ~= player and player.Is_Enemy(other) and self:on_map(other) then
            return true
        end
    end
    return false
end

function Reinforcements:withdraw(fleet)
    fleet.withdrawn = true
    local left = 0
    for _, copy in ipairs(fleet.copies or {}) do
        if copy.alive and TestValid(copy.object) then
            copy.gone = true
            left = left + 1
            if not pcall(copy.object.Hyperspace_Away, false) then
                pcall(copy.object.Despawn)
            end
        end
    end
    for _, index in ipairs(fleet.indices or {fleet.index}) do
        pcall(Engine_Inbound_Retreat, index)
    end
    log(fleet.owner .. " retreats: " .. left .. " ships jump out")
    for _, other in ipairs(self.fleets or {}) do
        if other.owner == fleet.owner and other.copies and not other.withdrawn then
            return
        end
    end
    self:left_battle(fleet.owner)
end

function Reinforcements:left_battle(owner)
    owner = string.upper(owner)
    if GONE[owner] then
        return
    end
    GONE[owner] = true
    local player = Find_Player(owner)
    local human = Find_Player("local")
    log(owner .. " has left the battle")
    if not player or player == human or player.Is_Ally(human) then
        return
    end
    for _, fleet in ipairs(self.fleets or {}) do
        local p = not fleet.arrived and Find_Player(fleet.owner)
        if p and p ~= human and not p.Is_Ally(human) and (p == player or p.Is_Ally(player)) and not self:on_map(p) then
            fleet.arrived, fleet.cancelled = true, true
            log(fleet.owner .. " fleet turns back with its side (" .. table.getn(fleet.types) .. " ships)")
        end
    end
end

function Reinforcements:note_retreats()
    self.engine_retreats = {}
    self.human_retreating = false
    if not Engine_Retreats then
        return
    end
    local ok, text_value = pcall(Engine_Retreats)
    local human = Find_Player("local")
    for _, line in ipairs(ok and split(text_value, "\n") or {}) do
        local _, _, owner, state, age = string.find(line, "^([^|]*)|([^|]*)|(.*)$")
        local player = owner and CAPS[string.upper(owner)] and Find_Player(owner)
        state = tonumber(state)
        if player == human then
            self.human_retreating = state == 2
        elseif player and state == 3 then
            self:left_battle(owner)
        elseif player and state == 2 then
            table.insert(self.engine_retreats, {owner = string.upper(owner), left = RETREAT_COUNTDOWN - (tonumber(age) or 0)})
        end
    end
end

local RQ_KEYS = {{"43", 4 / 3}, {"1610", 1.6}, {"169", 16 / 9}, {"219", 64 / 27}, {"329", 32 / 9}}
local RQ_ROWS = 4
local function rq_key()
    local w, h = 16, 9
    if Engine_Screen_Size then
        local ok, sw, sh = pcall(Engine_Screen_Size)
        if ok and sw and sh and sh > 0 then
            w, h = sw, sh
        end
    end
    local aspect, best, gap = w / h, "169", nil
    for _, k in ipairs(RQ_KEYS) do
        local d = k[2] - aspect
        if d < 0 then
            d = -d
        end
        if not gap or d < gap then
            best, gap = k[1], d
        end
    end
    return best
end

local rgb_of = {}
local function faction_rgb(owner)
    if rgb_of[owner] then
        return rgb_of[owner]
    end
    rgb_of[owner] = PALE
    if Engine_Faction_Colour then
        local ok, r, g, b = pcall(Engine_Faction_Colour, owner)
        if ok and r then
            rgb_of[owner] = {r, g, b}
        end
    end
    return rgb_of[owner]
end

function Reinforcements:countdowns(now)
    local lines, seen = {}, {}
    for _, fleet in ipairs(self.fleets or {}) do
        if fleet.retreat_at and not fleet.withdrawn and not seen[fleet.owner] then
            seen[fleet.owner] = true
            table.insert(lines, {owner = fleet.owner, left = fleet.retreat_at - now})
        end
    end
    for _, r in ipairs(self.engine_retreats or {}) do
        if not seen[r.owner] and r.left > 0 then
            seen[r.owner] = true
            table.insert(lines, r)
        end
    end
    table.sort(lines, function(a, b) return a.left < b.left end)
    show("dp_rt_q_shell", lines[1] and true or false)
    if not lines[1] and not self.countdowns_shown then
        return
    end
    self.countdowns_shown = lines[1] and true or nil
    local key = rq_key()
    local first = self.human_retreating and 2 or 1
    for _, k in ipairs(RQ_KEYS) do
        for i = 1, RQ_ROWS do
            local name = "dp_rt_q" .. k[1] .. "_" .. i
            local line = k[1] == key and i >= first and lines[i - first + 1]
            show(name, line and true or false)
            if line then
                text(name, label(line.owner) .. " retreating: " .. clock(line.left))
                local rgb = faction_rgb(line.owner)
                colour(name, rgb)
            end
        end
    end
end

return Reinforcements
