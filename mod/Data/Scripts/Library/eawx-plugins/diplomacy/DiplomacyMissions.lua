local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
require("eawx-plugins/diplomacy/DiplomacyAI")

local Missions = {}

local KINDS = {"PROTECT"}
local COLOR = {r = 150, g = 210, b = 255}

local function rules()
    return CONFIG.MISSIONS
end

local function weeks(n)
    return n * CONFIG.WEEK_SECONDS
end

local function pick(list)
    if table.getn(list) == 0 then
        return nil
    end
    return list[GameRandom.Free_Random(1, table.getn(list))]
end

local function mission_text(d, world, mission)
    local name = d:planet_name(FindPlanet(world))
    return "raiders threaten " .. name .. ". Keep warships in orbit for " .. rules().PROTECT_WEEKS .. " weeks."
end

local function open_appeals(d)
    local count = 0
    for name, appeal in pairs(d.appeals) do
        if GetCurrentTime() >= appeal.expires then
            d.appeals[name] = nil
            Missions.show_appeals(d)
            local planet = FindPlanet(name)
            if planet and planet.Get_Owner() == Find_Player("INDEPENDENT_FORCES") then
                d.show("Diplomacy: " .. d:planet_name(planet) .. "'s appeal to join went unanswered.", nil, COLOR)
                if appeal.republic and d.republic then
                    local ok_s, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
                    if ok_s and Sym then
                        pcall(Sym.change, d, name, -require("eawx-plugins/new-republic/RepublicConfig").COUNCIL.APPEAL_LAPSED)
                    end
                end
            end
        else
            count = count + 1
        end
    end
    return count
end

local function new_appeal(d)
    if not rules().APPEAL_FACTIONS[d.human.Get_Faction_Name()] or open_appeals(d) >= rules().MAX_APPEALS then
        return
    end
    local independent = Find_Player("INDEPENDENT_FORCES")
    if not independent or d.human.Is_Enemy(independent) then
        return
    end
    local ctx = DiplomacyAI.context(d.display_name)
    local candidates = {}
    local ok_s, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
    local RC = d.republic and require("eawx-plugins/new-republic/RepublicConfig")
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local name = string.upper(planet.Get_Type().Get_Name())
        local willing = true
        if RC then
            local v = ok_s and Sym and Sym.value(d, name)
            willing = v ~= nil and v >= RC.SYMPATHY_SYMPATHETIC
        end
        if willing and planet.Get_Owner() == independent and not d.appeals[name] then
            local jumps = DiplomacyAI.jumps_to(ctx, d.human, planet)
            if jumps and jumps <= 1 then
                table.insert(candidates, planet)
            end
        end
    end
    local planet = pick(candidates)
    if not planet then
        return
    end
    local name = string.upper(planet.Get_Type().Get_Name())
    local n = RC and RC.COUNCIL.APPEAL_WEEKS or rules().APPEAL_WEEKS
    d.appeals[name] = {expires = GetCurrentTime() + weeks(n), republic = RC ~= nil}
    Missions.show_appeals(d)
    local council = RC and d.senate and d.senate.council
    d.show("Appeal to Join: the people of " .. d:planet_name(planet) .. " ask to join the "
        .. d.display_name(d.human.Get_Faction_Name()) .. "."
        .. (council and " Put their petition to the Council within "
            or (RC and " Put their petition to the Senate within " or " Answer their petition within "))
        .. n .. " weeks.", nil, COLOR, 30)
end

function Missions.show_appeals(d)
    Story_Event("DIPLOMACY_APPEALS_HIDE")
    local plot = Get_Story_Plot("Conquests\\Events\\MissionRepository.xml")
    local event = plot and plot.Get_Event("Diplomacy_Appeals_Show")
    if not event then
        return
    end
    local any = false
    event.Clear_Dialog_Text()
    M.add_dialog(event, "Worlds asking to join the " .. d.display_name(d.human.Get_Faction_Name()))
    event.Add_Dialog_Text("TEXT_NONE")
    for name, appeal in pairs(d.appeals) do
        local planet = FindPlanet(name)
        if planet and GetCurrentTime() < appeal.expires then
            any = true
            local left = M.floor((appeal.expires - GetCurrentTime()) / CONFIG.WEEK_SECONDS)
            M.add_dialog(event, d:planet_name(planet) .. ": its people petition to join"
                .. ((appeal.republic and d.senate and d.senate.council)
                    and (appeal.approved and " (the Council approves)" or " (needs the Council's approval)") or "")
                .. ". " .. left .. " week(s) left.")
        end
    end
    event.Add_Dialog_Text("TEXT_NONE")
    M.add_dialog(event, (d.republic and "Pass its petition in the chamber: it becomes a protected world, and may "
        .. "later ask to become an associate."
        or "Answer its petition: it becomes an associate (vassal) world, and may later ask to become a full member."))
    if any then
        Story_Event("DIPLOMACY_APPEALS_SHOW")
    end
end

function Missions.answer_appeal(d, name)
    local appeal = d.appeals[name]
    if appeal and GetCurrentTime() < appeal.expires then
        d.appeals[name] = nil
        Missions.show_appeals(d)
        return true
    end
    return false
end

function Missions.has_appeal(d, name)
    local appeal = d.appeals[name]
    return appeal ~= nil and GetCurrentTime() < appeal.expires
end

function Missions.start(d, world, kind)
    local state = d.vassal_worlds[world]
    if not state then
        return
    end
    state.integration = state.integration or 0
    state.mission = {kind = kind, expires = GetCurrentTime() + weeks(rules().MISSION_WEEKS), progress = 0}
    local Goals = require("eawx-plugins/diplomacy/DiplomacyGoals")
    d.show("Integration mission: " .. mission_text(d, world, state.mission) .. " "
        .. Goals.weeks_line(state.mission.expires), nil, COLOR, 30)
    local planet = FindPlanet(world)
    local ok, slot = pcall(Goals.add, d, "Integration: " .. (planet and d:planet_name(planet) or world),
        {"Integration talks: " .. mission_text(d, world, state.mission)}, state.mission.expires)
    d.integration_goals = d.integration_goals or {}
    d.integration_goals[world] = ok and slot or nil
end

local function sweep_goals(d)
    for world, slot in pairs(d.integration_goals or {}) do
        local state = d.vassal_worlds[world]
        if not (state and state.mission) then
            pcall(require("eawx-plugins/diplomacy/DiplomacyGoals").remove, d, slot)
            d.integration_goals[world] = nil
        end
    end
end

local function content(state)
    state.content = state.content or rules().START_CONTENT
    return state.content
end

function Missions.adjust_content(d, world, amount)
    local state = d.vassal_worlds[world]
    if state then
        state.content = M.max(0, M.min(100, content(state) + amount))
    end
end

local function integrate(d, world)
    local planet = FindPlanet(world)
    d.vassal_worlds[world] = nil
    if not planet then
        return
    end
    if planet.Get_Owner() ~= d.human then
        d:transfer_world(planet, d.human, true)
    end
    d.integrated = d.integrated or {}
    d.integrated[world] = GetCurrentTime()
    local office = d.human.Get_Faction_Name() == "REBEL" and Find_Object_Type("Rebel_Office")
    if office then
        pcall(Spawn_Unit, office, planet, d.human)
    end
    d.show("Diplomacy: " .. d:planet_name(planet) .. " has joined the " .. d.display_name(d.human.Get_Faction_Name())
        .. " as a full member world, with its defenders.", nil, COLOR, 30)
end
Missions.integrate = integrate

local function check_integration(d, world)
    local state = d.vassal_worlds[world]
    if not state or state.stage == "associate" or (state.integration or 0) < rules().INTEGRATION_NEEDED
            or state.requests or state.petitions then
        return
    end
    if content(state) < rules().INTEGRATION_CONTENT then
        return
    end
    if state.stage == "protectorate" then
        state.petitions = true
        d.show("Republic: " .. d:planet_name(FindPlanet(world)) .. " has done its part and petitions to become an "
            .. "associate world. Put the petition to the " .. (d.senate.council and "Provisional Council" or "Senate")
            .. ".", nil, COLOR, 25)
        return
    end
    if not d:senate_active() then
        integrate(d, world)
        return
    end
    state.requests = true
    d.show("Diplomacy: " .. d:planet_name(FindPlanet(world)) .. " asks to become a full member world. Put the "
        .. "motion to the " .. (d.senate.council and "Provisional Council" or "Senate") .. " to admit it.", nil, COLOR, 25)
end

function Missions.credit(d, world)
    local state = d.vassal_worlds[world]
    if state then
        state.integration = (state.integration or 0) + 1
        check_integration(d, world)
    end
end

function Missions.integration_requests(d)
    local out = {}
    for world, state in pairs(d.vassal_worlds) do
        if state.requests and state.stage ~= "protectorate" and FindPlanet(world) then
            table.insert(out, world)
        end
    end
    table.sort(out)
    return out
end

local function mandate(d, amount)
    local ok, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
    if ok and Republic and Republic.senate_mandate then
        return Republic.senate_mandate(d, amount)
    end
    return false
end

local function mandate_step(d)
    local ok, R = pcall(require, "eawx-plugins/new-republic/RepublicConfig")
    return (ok and R and R.SENATE and R.SENATE.INTEGRATION_MANDATE) or 0
end

local function complete(d, world)
    local state = d.vassal_worlds[world]
    state.mission = nil
    state.mission_ended = GetCurrentTime()
    mandate(d, mandate_step(d))
    state.integration = (state.integration or 0) + 1
    state.content = M.min(100, content(state) + rules().MISSION_CONTENT)
    local name = d:planet_name(FindPlanet(world))
    d.show("Diplomacy: the mission at " .. name .. " is complete. Integration " .. M.min(state.integration,
        rules().INTEGRATION_NEEDED) .. "/" .. rules().INTEGRATION_NEEDED .. ", contentment " .. state.content .. ".",
        nil, COLOR)
    check_integration(d, world)
end

local function check_missions(d)
    sweep_goals(d)
    for world, state in pairs(d.vassal_worlds) do
        local mission = state.mission
        if mission then
            local planet = FindPlanet(world)
            if planet and DiplomacyAI.strength_at(d.human, planet) > 0 then
                mission.progress = mission.progress + 1
            end
            if mission.progress >= rules().PROTECT_WEEKS then
                complete(d, world)
            elseif GetCurrentTime() >= mission.expires then
                state.mission = nil
                state.mission_ended = GetCurrentTime()
                mandate(d, -mandate_step(d))
                state.content = M.max(0, content(state) - rules().MISSION_CONTENT)
                d.show("Diplomacy: the mission at " .. d:planet_name(planet) .. " failed. Its people are disappointed "
                    .. "(contentment " .. state.content .. ").", nil, COLOR)
            end
        end
    end
    sweep_goals(d)
end

local function council_rules(d)
    return (d.senate and d.senate.council) and true or false
end

local function new_integration_mission(d)
    local eligible = {}
    for world, state in pairs(d.vassal_worlds) do
        if not state.mission and state.stage ~= "associate" and (state.integration or 0) < rules().INTEGRATION_NEEDED
                and state.stage ~= "protectorate" then
            table.insert(eligible, world)
        end
    end
    local world = pick(eligible)
    if world then
        Missions.start(d, world, pick(KINDS))
    end
end

function Missions.talks_blocked(d, world)
    local state = d.vassal_worlds and d.vassal_worlds[world]
    if not state or state.stage ~= "protectorate" then
        return "Only a protected world can be brought towards the Republic."
    end
    if council_rules(d) then
        return "Integration talks open once the New Republic is founded."
    end
    if state.mission then
        return "An integration mission is already under way there."
    end
    if (state.integration or 0) >= rules().INTEGRATION_NEEDED then
        return "It has done its part: its petition comes next."
    end
    local ok_r, R = pcall(require, "eawx-plugins/new-republic/RepublicConfig")
    local wait = ok_r and R.SENATE and R.SENATE.INTEGRATION_WEEKS or 6
    if state.mission_ended and GetCurrentTime() - state.mission_ended < weeks(wait) then
        local left = M.ceil((state.mission_ended + weeks(wait) - GetCurrentTime()) / weeks(1))
        return "Its people need time after the last mission: " .. left .. " week" .. ((left == 1) and "" or "s") .. "."
    end
    local ok_s, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
    local v = ok_s and Sym and Sym.value(d, world)
    if not v or v < ((ok_r and R.SYMPATHY_SYMPATHETIC) or 60) then
        return "Its people are not Sympathetic to the Republic (sympathy " .. (v and M.round(v) or "unknown") .. ")."
    end
    return nil
end

function Missions.begin_talks(d, world)
    local why = Missions.talks_blocked(d, world)
    if why then
        return false, why
    end
    Missions.start(d, world, pick(KINDS))
    return true, "Integration talks begin."
end

function Missions.describe(d, world)
    local state = d.vassal_worlds[world]
    if not state then
        return "not an associate world"
    end
    local text = "integration " .. M.min(state.integration or 0, rules().INTEGRATION_NEEDED) .. "/"
        .. rules().INTEGRATION_NEEDED .. ", contentment " .. content(state)
    if state.requests then
        text = text .. "; asks to become a full member"
    elseif state.mission then
        text = text .. "; mission: " .. mission_text(d, world, state.mission)
    else
        text = text .. "; no mission yet"
    end
    return text
end

function Missions.associates(d)
    local out = {}
    for world, state in pairs(d.vassal_worlds) do
        local planet = FindPlanet(world)
        if planet then
            local status
            if state.petitions then
                status = "Petitions to become an associate world."
            elseif state.stage == "associate" and not state.requests then
                status = "Associate world: pays its share; may ask for a seat once content."
            elseif state.requests then
                status = "Asks to become a full member world."
            elseif state.mission then
                status = "Mission: " .. mission_text(d, world, state.mission) .. "."
            elseif (state.integration or 0) >= rules().INTEGRATION_NEEDED then
                status = "Missions done; needs contentment " .. rules().INTEGRATION_CONTENT .. " to ask to join."
            else
                status = "Waiting for its next mission."
            end
            table.insert(out, {world = world, name = d:planet_name(planet), content = content(state), stage = state.stage,
                               integration = M.min(state.integration or 0, rules().INTEGRATION_NEEDED),
                               needed = rules().INTEGRATION_NEEDED, status = status})
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function Missions.week(d)
    d.mission_weeks = (d.mission_weeks or 0) + 1
    check_missions(d)
    for world, state in pairs(d.vassal_worlds) do
        if not state.under_attack then
            state.content = M.min(100, content(state) + rules().WEEKLY_CONTENT)
        end
        check_integration(d, world)
    end
    local every = rules().EVERY_WEEKS
    if d.human.Get_Faction_Name() == "REBEL" and GlobalValue.Get("ChiefOfState") == "DUMMY_CHIEFOFSTATE_MOTHMA" then
        every = every - 1
    end
    if d.mission_weeks >= every then
        d.mission_weeks = 0
        new_appeal(d)
        new_integration_mission(d)
    end
end

function Missions.update(d)
    if GetCurrentTime() >= (d.next_mission_week or weeks(1)) then
        d.next_mission_week = M.next_week(weeks(1))
        Missions.week(d)
    end
end

return Missions
