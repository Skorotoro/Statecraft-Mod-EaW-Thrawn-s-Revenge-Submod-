local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local J = require("eawx-plugins/jedi-order/JediConfig")

local T = {}
T.RETRY, T.INITIATE_RETRY = 4, 3
T.ODDS = {PADAWAN = {50, 62, 75}, KNIGHT = {45, 58, 72}, INITIATE = {55, 70, 85}}
T.SHADOW_ODDS = 4
T.MIN, T.MAX = 10, 95
T.REPEAT_SHADOW = 3
T.INITIATE_LEAVE = 30
T.INITIATE_SHADOW = 4
T.INITIATE_TRAITS = {TEACHER = 10, PATIENT = 5, DISCIPLINED = 5, RECKLESS = -5, PROUD = -5, EMOTIONAL = -5}

T.TRIALS = {
    {key = "LONE_WATCH", rank = "PADAWAN", path = "GUARDIAN", name = "The Lone Watch", where = "MEMBER", weeks = 2, mod = 0,
     traits = {DUELLIST = 10, DISCIPLINED = 5, RECKLESS = -5},
     text = "Alone, they guard an outpost on {world} against the raiders who prey on it.",
     win = "{name} held the outpost on {world} alone until the raiders gave it up.",
     lose = "{name} could not hold the outpost on {world}.", fail = {death = 6, wound = 45, shadow = 3}},
    {key = "BEAST", rank = "PADAWAN", path = "GUARDIAN", name = "The Beast of the Wilds", where = "WILD", weeks = 2, mod = -5,
     traits = {DUELLIST = 10, PATIENT = 5, RECKLESS = -10},
     text = "A great beast is killing settlers on {world}. They must end it, or turn it away, alone.",
     win = "{name} faced the beast of {world} alone, and the settlers sleep again.",
     lose = "The beast of {world} was too much for {name}.", fail = {death = 10, wound = 55, shadow = 2}},
    {key = "PILGRIMS", rank = "PADAWAN", path = "GUARDIAN", name = "The Pilgrims' Road", where = "FORCE", weeks = 2, mod = 5,
     traits = {COMPASSIONATE = 5, DISCIPLINED = 5},
     text = "They escort pilgrims to the old Jedi places of {world}, through pirate-haunted lanes.",
     win = "{name} brought every pilgrim safely to {world} and home again.",
     lose = "Pirates scattered {name}'s pilgrims on the road to {world}.", fail = {death = 4, wound = 35, shadow = 3}},
    {key = "FIRE", rank = "PADAWAN", path = "GUARDIAN", name = "Fire in the Deep", where = "MEMBER", weeks = 1, mod = 0,
     traits = {COMPASSIONATE = 5, RECKLESS = 5},
     text = "A mine is burning on {world}, with miners trapped below. They go down alone.",
     win = "{name} brought the miners of {world} up out of the fire.",
     lose = "{name} could not reach all the miners of {world}.", fail = {death = 8, wound = 50, shadow = 4}},
    {key = "FEUD", rank = "PADAWAN", path = "CONSULAR", name = "A Village Divided", where = "MEMBER", weeks = 2, mod = 5,
     traits = {PEACEMAKER = 10, COMPASSIONATE = 5, PROUD = -10},
     text = "Two clans of {world} are a word from blood. They must make peace without drawing a blade.",
     win = "{name} made peace between the clans of {world}, with words alone.",
     lose = "The clans of {world} came to blows, and {name} drew their blade.", fail = {death = 2, wound = 15, shadow = 6}},
    {key = "SICK_WARD", rank = "PADAWAN", path = "CONSULAR", name = "The Sick Ward", where = "MEMBER", weeks = 2, mod = 0,
     traits = {COMPASSIONATE = 10, PATIENT = 5},
     text = "A fever has filled the wards of {world}. They tend the sick with the Force, alone.",
     win = "{name} turned the fever on {world}: the wards are emptying.",
     lose = "The fever on {world} ran its course, and {name} caught it.", fail = {death = 3, wound = 40, shadow = 3}},
    {key = "WARLORD", rank = "PADAWAN", path = "CONSULAR", name = "Words with a Warlord", where = "FOREIGN", weeks = 2, mod = -5,
     traits = {PEACEMAKER = 10, PROUD = -5, RECKLESS = -5},
     text = "A local strongman on {world} holds hostages. They go unarmed to talk him down.",
     win = "{name} talked the strongman of {world} into letting his hostages go.",
     lose = "The strongman of {world} would not listen to {name}.", fail = {death = 6, wound = 30, shadow = 4}},
    {key = "LOST_LESSON", rank = "PADAWAN", path = "CONSULAR", name = "The Lost Lesson", where = "FORCE", weeks = 2, mod = 5,
     traits = {SCHOLAR = 10, PATIENT = 5}, gain = {knowledge = 4},
     text = "They recover an old Jedi teaching from the ruins of {world}, and must understand it alone.",
     win = "{name} brought home a lost lesson from {world}, and understood it.",
     lose = "{name} found the ruins of {world}, but not the lesson.", fail = {death = 2, wound = 20, shadow = 3}},
    {key = "SPICE_TRAIL", rank = "PADAWAN", path = "SEEKER", name = "The Smugglers' Trail", where = "UNDERWORLD", weeks = 2, mod = -5,
     traits = {DISCIPLINED = 5, RECKLESS = -5},
     text = "Slavers took children from a Republic world; the trail leads to {world}. They follow it alone.",
     win = "{name} followed the slavers to {world} and brought the children home.",
     lose = "The slavers' trail went cold for {name} on {world}.", fail = {death = 6, wound = 40, shadow = 5}},
    {key = "INFORMANT", rank = "PADAWAN", path = "SEEKER", name = "The Quiet Informant", where = "MEMBER", weeks = 2, mod = 0,
     traits = {SCHOLAR = 5, PATIENT = 5, EMOTIONAL = -5},
     text = "Someone on {world} sells the Republic's secrets. They must find who, quietly.",
     win = "{name} found the informant on {world} without a shot fired.",
     lose = "The informant on {world} slipped away from {name}.", fail = {death = 3, wound = 25, shadow = 4}},
    {key = "STONES", rank = "PADAWAN", path = "SEEKER", name = "Listen to the Stones", where = "FORCE", weeks = 2, mod = 5,
     traits = {SCHOLAR = 5, INTUITIVE = 10},
     text = "A Jedi cache lies hidden on {world}. They must find it by the Force alone.",
     win = "{name} heard the stones of {world} and found the cache.",
     lose = "{name} listened to {world} and heard nothing.", fail = {death = 2, wound = 15, shadow = 4}},
    {key = "CAVE", rank = "PADAWAN", path = "SEEKER", name = "The Cave", where = "DARK", weeks = 1, mod = -5,
     traits = {PATIENT = 10, DISCIPLINED = 5, EMOTIONAL = -10, PROUD = -5},
     text = "There is a cave on {world} where the dark side shows each who enters what they fear. They go in alone.",
     win = "{name} faced what the cave of {world} showed them, and walked out.",
     lose = "{name} fled the cave of {world}, and something followed them out.", fail = {death = 0, wound = 0, shadow = 12}},

    {key = "LAST_STAND", rank = "KNIGHT", path = "GUARDIAN", name = "The Last Stand", where = "MEMBER", weeks = 3, mod = 0,
     traits = {DUELLIST = 5, DISCIPLINED = 10, RECKLESS = -5}, gain = {trust = 2},
     text = "Pirates besiege {world}. They lead its militia, and teach it to hold.",
     win = "{name} led the militia of {world} through the siege, and left it able to stand without them.",
     lose = "The siege of {world} broke {name}'s line.", fail = {death = 10, wound = 50, shadow = 4}},
    {key = "DARK_CHAMPION", rank = "KNIGHT", path = "GUARDIAN", name = "The Dark Champion", where = "DARK", weeks = 2, mod = -5,
     traits = {DUELLIST = 10, PATIENT = 5, PROUD = -5},
     text = "A Dark Jedi has made {world} his hunting ground. They face him alone, blade to blade.",
     win = "{name} beat the dark champion of {world}, and spared him.",
     lose = "The dark champion of {world} had the better of {name}.", fail = {death = 14, wound = 55, shadow = 8}},
    {key = "MILITIA", rank = "KNIGHT", path = "GUARDIAN", name = "The Teacher of Soldiers", where = "MEMBER", weeks = 3, mod = 5,
     traits = {TEACHER = 10, PATIENT = 5},
     text = "They train the defenders of {world}: forms, discipline, and when not to fight.",
     win = "{name} made soldiers of {world}'s defenders, and good ones.",
     lose = "{name} could not make {world}'s defenders listen.", fail = {death = 0, wound = 10, shadow = 3}},
    {key = "TERENTATEK", rank = "KNIGHT", path = "GUARDIAN", name = "The Terentatek", where = "WILD", weeks = 2, mod = -10,
     traits = {DUELLIST = 10, RECKLESS = -10},
     text = "A terentatek, bred by the Sith to hunt Jedi, has woken on {world}. They hunt it alone.",
     win = "{name} killed the terentatek of {world}.",
     lose = "The terentatek of {world} tore into {name}.", fail = {death = 14, wound = 60, shadow = 3}},
    {key = "PEACE_WORLDS", rank = "KNIGHT", path = "CONSULAR", name = "The Peace of Worlds", where = "FOREIGN", weeks = 3, mod = 0,
     traits = {PEACEMAKER = 10, PATIENT = 5, PROUD = -5}, gain = {trust = 3},
     text = "Two systems near {world} are at war. They must end it at the table.",
     win = "{name} ended the war at {world} with a treaty both sides keep.",
     lose = "The war at {world} went on, past {name}'s words.", fail = {death = 4, wound = 20, shadow = 4}},
    {key = "PLAGUE", rank = "KNIGHT", path = "CONSULAR", name = "The Healer's Burden", where = "MEMBER", weeks = 3, mod = 0,
     traits = {COMPASSIONATE = 10, PATIENT = 5},
     text = "A plague is killing {world}. They must lead its healers, and teach them what the Force can do.",
     win = "{name} broke the plague on {world}, and its healers learned from them.",
     lose = "The plague on {world} outran {name}, and their grief is heavy.", fail = {death = 4, wound = 40, shadow = 7}},
    {key = "LOST_TEACHING", rank = "KNIGHT", path = "CONSULAR", name = "The Forgotten Technique", where = "FORCE", weeks = 3, mod = 5,
     traits = {SCHOLAR = 10, TEACHER = 5}, gain = {knowledge = 10},
     text = "They rebuild a lost technique from the ruins of {world}, and must be able to teach it.",
     win = "{name} brought a forgotten technique back from {world}, ready to teach.",
     lose = "What {name} found on {world} was too broken to rebuild.", fail = {death = 2, wound = 15, shadow = 4}},
    {key = "BITTER_ONE", rank = "KNIGHT", path = "CONSULAR", name = "The Bitter One", where = "DARK", weeks = 2, mod = -5,
     traits = {COMPASSIONATE = 10, PEACEMAKER = 5, EMOTIONAL = -5}, gain = {initiate = true},
     text = "A gifted youth on {world} has turned bitter and dark. They must reach them, and bring them home.",
     win = "{name} reached the bitter one on {world}: they come to the Temple as an Initiate.",
     lose = "The bitter one on {world} turned on {name}.", fail = {death = 5, wound = 30, shadow = 10}},
    {key = "CULT", rank = "KNIGHT", path = "SEEKER", name = "The Shadow Cult", where = "MEMBER", weeks = 3, mod = 0,
     traits = {INTUITIVE = 10, DISCIPLINED = 5}, gain = {trust = 2},
     text = "A dark side cult hides among the people of {world}. They must find and break it.",
     win = "{name} unmasked the cult on {world} and broke it.",
     lose = "The cult on {world} went to ground, and marked {name}.", fail = {death = 6, wound = 30, shadow = 8}},
    {key = "TOMB", rank = "KNIGHT", path = "SEEKER", name = "The Sealed Tomb", where = "DARK", weeks = 2, mod = -5,
     traits = {SCHOLAR = 5, PATIENT = 10}, gain = {knowledge = 5},
     text = "A Sith tomb on {world} is breaking open. They must seal it again, alone.",
     win = "{name} sealed the tomb on {world} and learned from its walls.",
     lose = "The tomb on {world} breathed on {name}.", fail = {death = 8, wound = 30, shadow = 12}},
    {key = "LONG_HUNT", rank = "KNIGHT", path = "SEEKER", name = "The Long Hunt", where = "UNDERWORLD", weeks = 4, mod = -5,
     traits = {PATIENT = 10, RECKLESS = -5},
     text = "An assassin who has killed Jedi hides in the dens of {world}. They track him alone.",
     win = "{name} ran the assassin down on {world}.",
     lose = "The assassin of {world} found {name} first.", fail = {death = 12, wound = 45, shadow = 5}},
    {key = "MIRROR", rank = "KNIGHT", path = "SEEKER", name = "The Mirror", where = "DARK", weeks = 1, mod = -5,
     traits = {PATIENT = 10, INTUITIVE = 5, EMOTIONAL = -10, PROUD = -10}, gain = {lift = 10},
     text = "On {world} the dark side shows each Jedi what they could become. They must look, and turn away.",
     win = "{name} looked at their dark reflection on {world}, and turned away lighter.",
     lose = "{name} saw themselves on {world}, and could not look away.", fail = {death = 0, wound = 0, shadow = 15}},
}
T.UNDERWORLD = {"NAR_SHADDAA", "NAL_HUTTA", "KESSEL", "ORD_MANTELL", "TATOOINE", "RYLOTH", "UMBARA"}

local BY_KEY = {}
for _, t in ipairs(T.TRIALS) do
    BY_KEY[t.key] = t
end

local P = {}

function P.attach(Order)
    local function fill(line, p, world, d)
        line = string.gsub(line, "{name}", p.name)
        return (string.gsub(line, "{world}", world and Order.world_name(d, world) or "a distant world"))
    end

    function Order.trial_def(key)
        return BY_KEY[key]
    end

    function Order.xp_cap(p)
        return (p.rank == J.PADAWAN and J.XP_KNIGHT) or (p.rank == J.KNIGHT and J.XP_MASTER) or nil
    end

    function Order.cap_xp(p)
        local cap = Order.xp_cap(p)
        if cap and (p.xp or 0) > cap then
            p.xp = cap
        end
    end

    function Order.trial_blocked(d, s, p)
        local cap = Order.xp_cap(p)
        if not cap or (p.xp or 0) < cap then
            return "hidden"
        end
        if p.rank == J.KNIGHT and (p.missions or 0) < Order.trial_missions(s) then
            local n = Order.trial_missions(s) - (p.missions or 0)
            return p.name .. " needs " .. n .. " more mission" .. ((n == 1) and "" or "s") .. " before their trial."
        end
        local wait = (p.trial_at or 0) - s.week
        if wait > 0 then
            return p.name .. " can try their trial again in " .. wait .. ((wait == 1) and " week." or " weeks.")
        end
        return Order.busy(d, s, p)
    end

    local function worlds_for(d, s, rule)
        local out = {}
        local under = {}
        for _, w in ipairs(T.UNDERWORLD) do
            under[w] = true
        end
        local ok, planets = pcall(FindPlanet.Get_All_Planets)
        for _, planet in pairs(ok and planets or {}) do
            local w = U.key(planet)
            local mine = planet.Get_Owner() == d.human
            local force, side = Order.force_of(w), Order.side_of(w)
            local fit = (rule == "MEMBER" and mine) or (rule == "FORCE" and force >= 45 and side < 30)
                or (rule == "DARK" and side >= 40 and force >= 30) or (rule == "WILD" and not mine and force >= 20 and side < 40)
                or (rule == "UNDERWORLD" and under[w]) or (rule == "FOREIGN" and not mine)
            if fit and not Order.world_locked(w) and not Order.mission_at(s, w) then
                table.insert(out, w)
            end
        end
        return out
    end

    function Order.trial_of(d, s, p)
        local rank = (p.rank == J.PADAWAN) and "PADAWAN" or "KNIGHT"
        local t = p.trial and BY_KEY[p.trial.key]
        if t and t.rank == rank then
            return p.trial
        end
        local path = (rank == "PADAWAN") and (p.trial and p.trial.path or Order.knight_path(p)) or p.path or "GUARDIAN"
        local options = {}
        for _, def in ipairs(T.TRIALS) do
            if def.rank == rank and def.path == path and def.key ~= p.last_trial then
                local worlds = worlds_for(d, s, def.where)
                if worlds[1] then
                    table.insert(options, {def = def, worlds = worlds})
                end
            end
        end
        local pick = U.pick(options)
        if not pick then
            return nil
        end
        p.trial = {key = pick.def.key, world = U.pick(pick.worlds), path = path}
        return p.trial
    end

    function Order.trial_odds(d, s, p, def)
        local rank = (p.rank == J.PADAWAN) and "PADAWAN" or "KNIGHT"
        local odds = T.ODDS[rank][M.max(1, M.min(3, p.potential or 2))] + (def.mod or 0)
        for _, trait in ipairs(p.traits or {}) do
            odds = odds + ((def.traits or {})[trait] or 0)
        end
        odds = odds - M.floor((p.shadow or 0) / T.SHADOW_ODDS)
        return U.clamp(odds, T.MIN, T.MAX)
    end

    function Order.trial_tip(d, s, p)
        local tr = Order.trial_of(d, s, p)
        local def = tr and BY_KEY[tr.key]
        if not def then
            return nil
        end
        local f = def.fail
        local risks = {}
        if f.death > 0 then
            table.insert(risks, "death")
        end
        if f.wound > 0 then
            table.insert(risks, "wounds")
        end
        table.insert(risks, "darkness")
        return def.name .. " (" .. J.PATHS[def.path] .. "s' trial): " .. fill(def.text, p, tr.world, d) .. " Alone, "
            .. def.weeks .. ((def.weeks == 1) and " week" or " weeks") .. " there. Chance: " .. Order.trial_odds(d, s, p, def)
            .. "%. Failure risks " .. Order.names_of(risks) .. "."
    end

    function Order.start_trial(d, s, p)
        local why = Order.trial_blocked(d, s, p)
        if why then
            return (why ~= "hidden") and why or (p.name .. " is not ready for their trial.")
        end
        local tr = Order.trial_of(d, s, p)
        local def = tr and BY_KEY[tr.key]
        if not def then
            return "No world fit for " .. p.name .. "'s trial can be reached now."
        end
        local ok, text = Order.send_away(d, s, p, "TRIAL", tr.world, def.weeks, def.name)
        if not ok then
            return text
        end
        p.mission.trial = def.key
        text = Order.label(p) .. " leaves alone for their trial: " .. def.name .. " at " .. Order.world_name(d, tr.world) .. "."
        Order.news(s, text)
        return text
    end

    local function darken(p, amount)
        local susc = Order.susceptibility and Order.susceptibility(p) or 1
        Order.raise_shadow(p, M.max(0, M.round(amount * susc)))
    end

    function Order.trial_done(d, s, p, m)
        local def = BY_KEY[m.trial]
        m.stage, m.steered = "back", nil
        if not def then
            return
        end
        p.trial, p.last_trial = nil, def.key
        if U.chance(Order.trial_odds(d, s, p, def)) then
            p.trial_fails = nil
            local g = def.gain or {}
            local extra = ""
            if g.trust then
                Order.change_trust(s, g.trust)
                extra = extra .. " Public Trust +" .. g.trust .. "."
            end
            if g.knowledge then
                s.knowledge = s.knowledge + g.knowledge
                extra = extra .. " Knowledge +" .. g.knowledge .. "."
            end
            if g.lift then
                p.shadow = M.max(0, p.shadow - g.lift)
            end
            if g.initiate and Order.found_student then
                local q = Order.found_student(d, s, m.world)
                extra = extra .. " " .. q.name .. " comes to the Temple as an Initiate."
            end
            if p.rank == J.PADAWAN then
                Order.knight(s, p)
                p.path = def.path
                Order.say(d, s, fill(def.win, p, m.world, d) .. " They are a Jedi Knight now, of the Path of the "
                    .. J.PATHS[p.path] .. "." .. extra, Order.GOLD)
                if Order.promoted then
                    Order.promoted(d, s, p, J.PADAWAN)
                end
            else
                Order.say(d, s, fill(def.win, p, m.world, d) .. " They return a Jedi Master, ready to teach." .. extra, Order.GOLD)
                Order.make_master(d, s, p)
            end
            return
        end
        p.trial_fails = (p.trial_fails or 0) + 1
        p.trial_at = s.week + T.RETRY
        local f = def.fail
        darken(p, f.shadow + T.REPEAT_SHADOW * (p.trial_fails - 1))
        local text = fill(def.lose, p, m.world, d)
        if Order.mission_fall and Order.mission_fall(d, s, p, m) then
            return
        end
        if U.chance(f.death * Order.death_mult(s)) then
            Order.home_now(d, s, p)
            Order.kill(d, s, p, "lost on their trial at " .. Order.world_name(d, m.world) .. ".")
        elseif U.chance(f.wound) then
            Order.wound(s, p)
            Order.say(d, s, text .. " They are coming home wounded, and may try again in " .. T.RETRY .. " weeks.", Order.WARN)
        else
            Order.say(d, s, text .. " They may try again in " .. T.RETRY .. " weeks.", Order.WARN)
        end
    end

    function Order.initiate_trial_blocked(s, p)
        local wait = (p.trial_at or 0) - s.week
        return (wait > 0) and (p.name .. " can face the Jedi Trials again in " .. wait .. ((wait == 1) and " week." or " weeks.")) or nil
    end

    function Order.begin_initiate_trial(d, s, master, p)
        local why = Order.initiate_trial_blocked(s, p)
        if why then
            return false, why
        end
        p.master, p.trials_until = master.id, s.week + 1
        local text = p.name .. " faces the Jedi Trials on the Temple's grounds, with " .. master.name .. " watching."
        Order.news(s, text)
        return true, text
    end

    function Order.initiate_odds(d, s, p)
        local odds = T.ODDS.INITIATE[M.max(1, M.min(3, p.potential or 2))]
        local master = p.master and Order.get(s, p.master)
        for _, trait in ipairs(p.traits or {}) do
            odds = odds + (T.INITIATE_TRAITS[trait] or 0)
        end
        if master and Order.has_trait(master, "TEACHER") then
            odds = odds + T.INITIATE_TRAITS.TEACHER
        end
        return U.clamp(odds - M.floor((p.shadow or 0) / T.SHADOW_ODDS), T.MIN, T.MAX)
    end

    function Order.trials_week(d, s)
        local done = {}
        for _, p in ipairs(s.roster) do
            if p.rank == J.INITIATE and p.trials_until and s.week >= p.trials_until then
                table.insert(done, p)
            end
        end
        for _, p in ipairs(done) do
            p.trials_until = nil
            local master = p.master and Order.get(s, p.master)
            if master and U.chance(Order.initiate_odds(d, s, p)) then
                local ready = (Order.seated_in and Order.seated_in(s, "TRAINING")) or s.initiates_ready
                p.rank, p.xp, p.trial_fails = J.PADAWAN, ready and J.TRAINING_START_XP or 0, nil
                Order.say(d, s, p.name .. " has passed the Jedi Trials, and is now the Padawan of " .. master.name .. ".", Order.GOLD)
            else
                p.master = nil
                p.trial_fails = (p.trial_fails or 0) + 1
                local leave = T.INITIATE_LEAVE + (Order.has_trait(p, "PROUD") and 15 or 0) - (Order.has_trait(p, "PATIENT") and 15 or 0)
                if U.chance(leave) then
                    for i, other in ipairs(s.roster) do
                        if other == p then
                            table.remove(s.roster, i)
                            break
                        end
                    end
                    Order.say(d, s, p.name .. " failed the Jedi Trials and, disappointed, has left the Order.", Order.WARN)
                else
                    p.trial_at = s.week + T.INITIATE_RETRY
                    darken(p, T.INITIATE_SHADOW + T.REPEAT_SHADOW * (p.trial_fails - 1))
                    Order.say(d, s, p.name .. " failed the Jedi Trials. They may try again in " .. T.INITIATE_RETRY
                        .. " weeks, if a Master takes them.", Order.WARN)
                end
            end
        end
    end
end

P.T = T
return P
