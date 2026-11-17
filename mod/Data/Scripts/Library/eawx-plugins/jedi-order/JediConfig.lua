local J = {}

J.RANKS = {"Initiate", "Padawan", "Knight", "Master", "Grand Master"}
J.INITIATE, J.PADAWAN, J.KNIGHT, J.MASTER, J.GRAND_MASTER = 1, 2, 3, 4, 5
J.PATHS = {GUARDIAN = "Guardian", CONSULAR = "Consular", SEEKER = "Sentinel"}
J.PATH_ORDER = {"GUARDIAN", "CONSULAR", "SEEKER"}
J.PATH_TEXT = {
    GUARDIAN = "Guardians stand between the galaxy and its dangers: best at Confronting the Darkness.",
    CONSULAR = "Consulars heal and make peace: best at Mediating and Keeping the Peace.",
    SEEKER = "Sentinels look for what was lost and hidden: best at Seeking the Force and Recovering the Lore.",
}
J.PATH_ICON = {GUARDIAN = "dp_jp_jedi_guardian.tga", CONSULAR = "dp_jp_jedi_consular.tga", SEEKER = "dp_jp_jedi_sentinel.tga"}
J.STUDENT_ICON = "dp_jp_jedi_consular.tga"
J.PATH_ICON_F = {GUARDIAN = "dp_jp_jedi_guardian_f.tga", CONSULAR = "dp_jp_jedi_consular_f.tga", SEEKER = "dp_jp_jedi_sentinel.tga"}
J.PATH_ICON_M = {GUARDIAN = "dp_jp_jedi_guardian.tga", CONSULAR = "dp_jp_jedi_consular.tga", SEEKER = "dp_jp_jedi_sentinel_m.tga"}
J.STUDENT_ICON_F = "dp_jp_jedi_consular_f.tga"
J.INITIATE_ICON = "dp_jp_smuggler.tga"
J.VACANT_ICON = "dp_jp_jedi_temple.tga"
J.FALLEN_ICON = "dp_jp_dark_jedi.tga"
J.POTENTIAL = {{name = "Slow", rate = 0.75}, {name = "Moderate", rate = 1}, {name = "Fast", rate = 1.5}}

J.START_TRUST = 40
J.TRUST_HIGH, J.TRUST_LOW = 80, 20
J.INITIATE_CAP, J.INITIATE_CAP_TAUGHT = 6, 10
J.XP_WEEK, J.XP_ALONE = 10, 5
J.XP_BY_POTENTIAL = {2.5, 5, 10}
J.MISSION_XP_RATE = {0.5, 1, 1.5}
J.XP_KNIGHT, J.XP_MASTER = 160, 480
J.XP_SUCCESS, J.XP_FAILURE = 20, 8
J.STUDENTS = 2
J.REPAIR_WEEKS = 8
J.TRIAL_MISSIONS, J.TRIAL_RETRY_WEEKS = 5, 8
J.REST_WEEKS = 2
J.REST_SHADOW = 5
J.UPKEEP = 20
J.WOUND_WEEKS = 8
J.UNIT_SLOTS = 20
J.WEEK_SECONDS = 40
J.LOST_SECONDS = 20
J.LEG_SECONDS = 120
J.FALLEN_TYPES = 4
J.COUNCIL_MASTERS = 3
J.COUNCIL_ASK_AGAIN = 26
J.COUNCIL_REPLACE_WEEKS = 8
J.CRISIS_WEEKS, J.CRISIS_CHANCE = 4, 8
J.SENATE_ORDER_WEEKS = 20
J.FUND_WEEKS = 52

J.SHADOW = {SIGN = 35, SENSE = 40, WARN = 60, EDGE = 85, REST = 2, MASTER = 1, ASSIGNED = 3, GRIEF = 20, CONFRONT = 15,
            DARK_SITE = 8, STUDY = 3, WOUND_NEAR = 6, PEER_DEATH = 15, PASSED = 6, DARK_EVENT = 50, DARK_EVENT_RATE = 0.25,
            FALL = 65, FALL_RATE = 1.5, COUNSEL = 15, RETREAT = 5, RETREAT_WEEKS = 4, COUNSEL_WEEKS = 2}
J.SHADOW_WORDS = {{20, "Clear"}, {40, "Uneasy"}, {60, "Disturbance"}, {1000, "Dark"}}
J.ORDER_SHADOW = {DARKNESS_FADE = 1, KNOWN_WEEKS = 26, FALLEN_DARKNESS = 1, LEAD_DARKNESS = 5,
                  DARK_LEADS = {1, 1.5, 2, 2.5}, XP = {1, 1, 0.8, 0.65}, TRUST = {0, 0, -1, -2}, ODDS = {0, 0, -5, -15},
                  STUDENTS = {0, 0, 1, 2}, EVENTS = {1, 1.25, 1.5, 2}, EDGE_PUSH = {0, 0, 0, 8}}
J.VIGIL_WEEKS, J.VIGIL_SHADOW, J.VIGIL_DARKNESS, J.VIGIL_EVERY = 2, 10, 5, 20
J.SMALL_CHANCE = 6
J.SMALL_DARK = {{"{name} lost their temper with a dockworker over nothing.", 4}, {"{name} dreamed of fire, and woke angry.", 5},
                {"{name} won an argument with a Master, and enjoyed it too much.", 3},
                {"{name} heard a holonet report on Imperial atrocities and has not slept since.", 5},
                {"{name} snapped at a younger student.", 3}, {"{name} spends hours alone with the old Massassi carvings.", 6},
                {"{name} wonders aloud why the Jedi let the Empire win.", 4}, {"{name} broke a training remote in frustration.", 3},
                {"A letter from home has left {name} bitter.", 5}, {"{name} enjoyed a duel more than a Jedi should.", 4}}
J.SMALL_LIGHT = {{"{name} spent the night by the lake, and came back at peace.", 4},
                 {"{name} helped the Temple's cooks all week without being asked.", 3},
                 {"{name} sat with a sick child from the pilgrims' camp.", 5}, {"{name} laughed for the first time in weeks.", 3},
                 {"{name} found an old meditation in the archives and has taken to it.", 4},
                 {"{name} apologised to a rival, and meant it.", 5}, {"{name} spent a day in the jungle with the Massassi trees.", 3},
                 {"A student thanked {name} for their patience.", 4}}
J.TURN_RATE = 0.2
J.FALL_KILL, J.FALL_WOUND = 10, 20

J.TRAITS = {
    COMPASSIONATE = {name = "Compassionate", text = "Shadow fades faster."},
    DISCIPLINED = {name = "Disciplined", text = "Shadow rises more slowly."},
    RECKLESS = {name = "Reckless", text = "Missions +5% to succeed, but the shadow rises while on them."},
    PROUD = {name = "Proud", text = "The shadow rises while on missions."},
    GRIEVING = {name = "Grieving", text = "The shadow rises while on missions; a loss hits harder."},
    SCHOLAR = {name = "Scholar", text = "Recover the Lore +15%; more Knowledge from it."},
    PEACEMAKER = {name = "Peacemaker", text = "Mediate and Keep the Peace +15%."},
    DUELLIST = {name = "Duellist", text = "Confront the Darkness +15%."},
    TEACHER = {name = "Teacher", text = "Their students gain Training XP a quarter faster."},
    EMOTIONAL = {name = "Emotional", text = "Feels everything deeply: losses and slights darken them more."},
    COMPETITIVE = {name = "Competitive", text = "Must be first: being passed over darkens them."},
    PATIENT = {name = "Patient", text = "Waits, listens, endures: the dark side finds little purchase."},
    INTUITIVE = {name = "Intuitive", text = "Senses the darkness in others: at the Temple they see a troubled Jedi's shadow for what it is."},
}
J.TRAIT_ORDER = {"COMPASSIONATE", "DISCIPLINED", "RECKLESS", "PROUD", "GRIEVING", "SCHOLAR", "PEACEMAKER", "DUELLIST", "TEACHER",
                 "EMOTIONAL", "COMPETITIVE", "PATIENT"}
J.SUSCEPTIBLE = {RANK = {1.25, 1.35, 1.0, 0.7, 0.5},
                 TRAIT = {RECKLESS = 0.2, PROUD = 0.2, EMOTIONAL = 0.3, COMPETITIVE = 0.2, GRIEVING = 0.2,
                          DISCIPLINED = -0.3, PATIENT = -0.3, COMPASSIONATE = -0.2},
                 MISSION_EASE = 0.02, MISSION_EASE_MAX = 0.3, MIN = 0.3, MAX = 2.0}

J.HEROES = {
    {key = "LUKE", icon = "dp_jp_luke_skywalker.tga", name = "Luke Skywalker", species = "Human", home = "Tatooine", units = {"LUKE_SKYWALKER_JEDI", "LUKE_SKYWALKER_JEDI_TEAM", "LUKE_JEDI_XWING"},
     rank = {{0, 5}}, path = "GUARDIAN", potential = 3, traits = {"COMPASSIONATE", "TEACHER", "INTUITIVE"}, always = 0},
    {key = "MARA", icon = "dp_jp_mara_jade.tga", name = "Mara Jade", species = "Human", home = "Coruscant", units = {"MARA_JADE_LIGHTSABER", "MARA_SABER_TEAM"},
     rank = {{0, 3}, {19, 4}}, path = "GUARDIAN", potential = 3, traits = {"DISCIPLINED", "DUELLIST"}},
    {key = "KYLE", icon = "dp_jp_kyle_katarn.tga", name = "Kyle Katarn", species = "Human", home = "Sulon", units = {"KYLE_KATARN_LIGHTSABER", "KYLE_KATARN_BLASTER", "KYLE_KATARN_DUMMY", "KATARN_TEAM"},
     rank = {{0, 4}}, path = "GUARDIAN", potential = 3, traits = {"DUELLIST", "RECKLESS"}, always = 5},
    {key = "CORRAN", icon = "dp_jp_horn.tga", name = "Corran Horn", species = "Human", home = "Corellia", units = {"CORRAN_HORN", "CORRAN_HORN_TEAM", "CORRAN_XWING"},
     rank = {{0, 3}, {19, 4}}, path = "GUARDIAN", potential = 2, traits = {"PROUD", "DISCIPLINED"}},
    {key = "CILGHAL", icon = "dp_jp_cilghal.tga", name = "Cilghal", species = "Mon Calamari", home = "Mon Calamari", units = {"CILGHAL", "CILGHAL_TEAM"},
     rank = {{0, 3}, {14, 4}}, path = "CONSULAR", potential = 3, traits = {"COMPASSIONATE", "PEACEMAKER"}},
    {key = "ZUMA", icon = "dp_jp_zuma.tga", name = "Mander Zuma", species = "Human", home = "Coruscant", units = {"MANDER_ZUMA", "ZUMA_TEAM"},
     rank = {{0, 3}}, path = "CONSULAR", potential = 2, traits = {"PEACEMAKER"}},
}

J.CLASS = {
    {key = "KAM", name = "Kam Solusar", species = "Human", home = "Tatooine", from = 10, rank = {{10, 3}, {14, 4}}, path = "GUARDIAN", potential = 2, traits = {"DISCIPLINED"}},
    {key = "BRAND", name = "Empatojayos Brand", species = "Human", home = "Ossus", from = 10, to = 11, rank = {{10, 4}}, path = "GUARDIAN", potential = 2, traits = {"PATIENT", "DISCIPLINED"}},
    {key = "VIMA", female = true, name = "Vima-Da-Boda", species = "Human", home = "Nar Shaddaa", from = 10, rank = {{10, 4}}, path = "CONSULAR", potential = 2, traits = {"GRIEVING", "COMPASSIONATE"}, shadow = 15},
    {key = "JEM", female = true, name = "Jem Ysanna", species = "Human", home = "Ossus", from = 10, rank = {{10, 2}, {13, 3}}, path = "SEEKER", potential = 2, traits = {"DISCIPLINED"}},
    {key = "RAYF", name = "Rayf Ysanna", species = "Human", home = "Ossus", from = 10, rank = {{10, 2}, {14, 3}}, path = "GUARDIAN", potential = 2, traits = {"RECKLESS"}},
    {key = "DORSK", name = "Dorsk 81", species = "Khommite", home = "Khomm", from = 11, to = 12, rank = {{11, 2}}, path = "CONSULAR", potential = 2, traits = {"EMOTIONAL"}},
    {key = "BRAKISS", name = "Brakiss", species = "Human", home = "Coruscant", from = 11, to = 13, rank = {{11, 2}}, path = "SEEKER", potential = 3, traits = {"PROUD", "COMPETITIVE"}, shadow = 35, spy = true},
    {key = "IKRIT", name = "Ikrit", species = "Kushiban", home = "Kushibah", from = 22, rank = {{22, 4}}, path = "SEEKER", potential = 2, traits = {"PATIENT", "INTUITIVE"}},
    {key = "GANNER", name = "Ganner Rhysode", species = "Human", home = "Coruscant", from = 25, rank = {{25, 3}}, path = "GUARDIAN", potential = 2, traits = {"PROUD", "COMPETITIVE"}},
    {key = "TIONNE", female = true, name = "Tionne", species = "Human", home = "Rindao", from = 11, rank = {{11, 2}, {13, 3}, {19, 4}}, path = "SEEKER", potential = 2, traits = {"SCHOLAR", "TEACHER"}},
    {key = "STREEN", name = "Streen", species = "Human", home = "Bespin", from = 11, rank = {{11, 2}, {14, 3}, {22, 4}}, path = "CONSULAR", potential = 2, traits = {"GRIEVING"}},
    {key = "KIRANA", female = true, name = "Kirana Ti", species = "Human", home = "Dathomir", from = 11, rank = {{11, 2}, {14, 3}, {19, 4}}, path = "GUARDIAN", potential = 2, traits = {"DUELLIST"}},
    {key = "CRAY", female = true, name = "Cray Mingla", species = "Human", home = "Coruscant", from = 11, to = 12, rank = {{11, 2}}, path = "CONSULAR", potential = 2, traits = {"COMPASSIONATE", "PEACEMAKER"}},
    {key = "KYP", name = "Kyp Durron", species = "Human", home = "Deyer", from = 11, rank = {{11, 2}, {13, 3}, {19, 4}}, path = "GUARDIAN", potential = 3, traits = {"PROUD", "RECKLESS"}, shadow = 20},
    {key = "JADEN", name = "Jaden Korr", species = "Human", home = "Coruscant", from = 11, rank = {{11, 2}, {15, 3}}, path = "GUARDIAN", potential = 3, traits = {"DUELLIST"}, master = "KYLE"},
    {key = "ROSH", name = "Rosh Penin", species = "Human", home = "Corellia", from = 11, rank = {{11, 2}, {15, 3}}, path = "GUARDIAN", potential = 2, traits = {"PROUD", "RECKLESS"}, shadow = 15, master = "KYLE"},
    {key = "GANTORIS", name = "Gantoris", species = "Human", home = "Eol Sha", from = 11, to = 11, rank = {{11, 2}}, path = "GUARDIAN", potential = 2, traits = {"PROUD", "GRIEVING"}, shadow = 25},
    {key = "JACEN", name = "Jacen Solo", species = "Human", home = "Coruscant", from = 19, rank = {{19, 2}, {25, 3}}, path = "SEEKER", potential = 3, traits = {"COMPASSIONATE"}},
    {key = "JAINA", female = true, name = "Jaina Solo", species = "Human", home = "Coruscant", from = 19, rank = {{19, 2}, {25, 3}}, path = "GUARDIAN", potential = 3, traits = {"RECKLESS"}, master = "MARA"},
    {key = "ANAKIN", name = "Anakin Solo", species = "Human", home = "Coruscant", from = 21, rank = {{21, 1}, {23, 2}, {26, 3}}, path = "GUARDIAN", potential = 3, traits = {"PROUD"}},
    {key = "TENEL", female = true, name = "Tenel Ka", species = "Human", home = "Dathomir", from = 19, rank = {{19, 2}, {25, 3}}, path = "GUARDIAN", potential = 2, traits = {"DISCIPLINED", "DUELLIST"}},
    {key = "LOWBACCA", name = "Lowbacca", species = "Wookiee", home = "Kashyyyk", from = 19, rank = {{19, 2}, {25, 3}}, path = "SEEKER", potential = 2, traits = {"SCHOLAR"}},
    {key = "RAYNAR", name = "Raynar Thul", species = "Human", home = "Alderaan", from = 20, rank = {{20, 1}, {23, 2}, {26, 3}}, path = "CONSULAR", potential = 2, traits = {"PROUD"}},
    {key = "TAHIRI", female = true, name = "Tahiri Veila", species = "Human", home = "Tatooine", from = 21, rank = {{21, 1}, {24, 2}}, path = "SEEKER", potential = 2, traits = {"RECKLESS"}},
}
J.FIRST_YEAR = 10
J.NAMED_CHANCE, J.NAMED_ARRIVE = 12, 30

J.FIRST_NAMES = {"Asyr", "Bren", "Corwin", "Dalia", "Ereth", "Fenn", "Garen", "Halia", "Ilsa", "Joren", "Kessa", "Lorn",
                 "Mirel", "Nessa", "Orin", "Pell", "Quill", "Rhea", "Soren", "Talya", "Ulric", "Vena", "Wynn", "Yara", "Zev"}
J.LAST_NAMES = {"Arden", "Brandt", "Corvane", "Dacre", "Elanor", "Farro", "Galen", "Horne", "Ireth", "Jorran", "Keld", "Lorrin",
                "Maran", "Nalle", "Orrin", "Pallan", "Quen", "Rhand", "Sarne", "Tarrow", "Ulan", "Vael", "Wren", "Xan", "Zarro",
                "Ashgrove", "Bellam", "Carrick", "Desmar", "Everet", "Fallow", "Grail", "Halcro", "Istvan", "Jarrow",
                "Kestrel", "Lanver", "Marrok", "Norwell", "Oakhart", "Penhal", "Ravel", "Stellan", "Thorne", "Usk",
                "Varro", "Westerly", "Yarrow", "Calder", "Drennan", "Morrow", "Sallis", "Tennant", "Voss", "Harlan"}

J.FORCE_DEFAULT, J.FORCE_BARREN = 5, 2
J.LORE_FORCE = 50
J.DARK_SITE = 50
J.SIDE_SHADOW = 20
J.SEEK_HINTS = {[60] = "the Force is strong here, the Jedi felt it from orbit",
                [40] = "something stirs here; the Jedi felt it among the people",
                [0] = "the Force is quiet here"}

J.RUINS = {
    {world = "OSSUS", name = "the Great Library of Ossus", knowledge = 18},
    {world = "TYTHON", name = "the first temples of Tython", knowledge = 16},
    {world = "DATHOMIR", name = "the wreck of the Chu'unthor", knowledge = 14},
    {world = "YAVIN", name = "the Massassi temples of Yavin", knowledge = 12, dark = true},
    {world = "KORRIBAN", name = "the Valley of the Dark Lords", knowledge = 20, dark = true},
    {world = "ZIOST", name = "the Sith ruins of Ziost", knowledge = 18, dark = true},
    {world = "DANTOOINE", name = "the old enclave of Dantooine", knowledge = 12},
    {world = "CORUSCANT", name = "the ruined Jedi Temple", knowledge = 12},
    {world = "BYSS", name = "the Emperor's vaults on Byss", knowledge = 20, dark = true},
}
J.HOLOCRON_CHANCE, J.HOLOCRON_KNOWLEDGE = 15, 20

J.MISSIONS = {
    SEEK = {name = "Seek the Force", tier = 1, best = {SEEKER = true}, weeks = 1.5, icon = "dp_mi_seek.tga", base = 80, death = 1,
            open = true, short = "Search a world for what the Force hides there: a student, a lead, old writings, a place of calm.",
            text = "Search a world for what the Force hides there: a student for the Temple, a lead to follow, old writings, "
                .. "a healers' tradition, a place of calm, or a dark presence. What turns up depends on how strong the Force "
                .. "is there and which side holds it; a lead about the world makes the search surer."},
    MEDIATE = {name = "Mediate", tier = 1, best = {CONSULAR = true}, weeks = 1, icon = "dp_mi_mediate.tga", base = 60, death = 2,
               trust_risk = true, short = "Calm a world in unrest: opinion +15, secession talk cools, integration moves on.",
               text = "Calm a member world or a protectorate in unrest. Success: opinion +15 (fading over 12 weeks), its talk "
                   .. "of secession cools, and a protectorate's integration moves on by one mission."},
    ANSWER = {name = "Answer a Call", tier = 1, best = {}, weeks = 1, icon = "dp_mi_answer.tga", base = 70, death = 1,
              law = "JEDI_SANCTION", event = true, trust_risk = true,
              short = "Answer a bloc's request in person: the bloc and the Mandate rise as if you had met it.",
              text = "Answer a Senate bloc's request in person, one a Jedi can meet (peace, protecting a world, uniting a "
                  .. "sector). Success grants the request: the bloc's opinion and the Mandate rise as if the government "
                  .. "had met it, and Public Trust too. Needs the Jedi Sanction Act."},
    PEACE = {name = "Keep the Peace", tier = 2, best = {CONSULAR = true, GUARDIAN = true}, weeks = 1.5, icon = "dp_mi_peace.tga", base = 55, death = 4,
             trust_risk = true, short = "Hold a troubled world for 12 weeks (opinion +10, influence +2), or win sympathy +10.",
             text = "Hold a troubled world. Success on your own world: influence +2 and opinion +10 for 12 weeks, so it "
                 .. "will not rise. On a world you do not hold: sympathy +10."},
    LORE = {name = "Recover the Lore", tier = 2, best = {SEEKER = true}, weeks = 2, icon = "dp_mi_lore.tga", base = 60, death = 4,
            short = "Search a ruin or an archive for Knowledge, perhaps a holocron. Dark sites darken whoever goes.",
            text = "Search a ruin or an old archive. Success: Knowledge, and perhaps a holocron. Dark sites raise the shadow "
                .. "of whoever goes."},
    ENVOY = {name = "Envoy of the Republic", tier = 2, best = {CONSULAR = true}, weeks = 2, icon = "dp_mi_envoy.tga", base = 60, death = 2,
             law = "JEDI_SANCTION", event = true, trust_risk = true,
             short = "Speak for the Republic: a power's opinion +10 at its capital, or sympathy +10 elsewhere.",
             text = "Speak for the Republic at another power's court, or among a people it does not rule. Success at a "
                 .. "power's capital: its opinion of the Republic +10 (with the Delegates' work, up to +25). On a world the "
                 .. "Republic does not hold: sympathy +10. Needs the Jedi Sanction Act."},
    CONFRONT = {name = "Confront the Darkness", tier = 3, best = {GUARDIAN = true}, weeks = 1.5, icon = "dp_mi_confront.tga", master = true, base = 35, death = 35,
                trust_risk = true, short = "Face a named dark threat: success ends it; failure can kill. The deadliest mission.",
                text = "Face a named dark threat. Success ends it, Public Trust rises and the Order's darkness lifts a "
                    .. "little; failure can kill. The deadliest mission there is, and it raises the shadow of whoever goes."},
    REDEEM = {name = "Redeem the Fallen", tier = 3, best = {CONSULAR = true}, weeks = 2, icon = "dp_mi_redeem.tga", master = true, base = 35, death = 15,
              trust_risk = true, short = "Bring a fallen Jedi home as a Knight; their dark company is gone. Failure can kill.",
              text = "Try to bring a fallen Jedi home. Success: they return to the Order as a Knight, and their dark "
                  .. "company is gone. Failure can kill."},
    CLEANSE = {name = "Cleanse a Dark Site", tier = 3, best = {SEEKER = true, GUARDIAN = true}, weeks = 2, icon = "dp_mi_cleanse.tga", master = true, base = 45, death = 10,
               trust_risk = true, short = "Seal a dark site: its darkness -30, the Order's -10. The cure for the Shadow.",
               text = "Seal a place where the dark side pools. Success: the world's darkness -30, the Order's darkness -10, "
                   .. "and the Exar Kun matter is ended if it is Yavin's old temple. No Knowledge comes of it. The only "
                   .. "direct cure for the Shadow over the Order."},
}
J.MISSIONS.TRIAL = {name = "Trial", weeks = 2, tier = 1, death = 0, free = true}
J.MISSIONS.POST = {name = "Post", weeks = 1, tier = 1, death = 0, free = true}
J.MISSIONS.RETREAT = {name = "Retreat", weeks = 4, tier = 1, death = 0, free = true}
J.MISSION_ORDER = {"SEEK", "MEDIATE", "ANSWER", "PEACE", "LORE", "ENVOY", "CONFRONT", "REDEEM", "CLEANSE"}
J.TIER_NAMES = {"Tier I", "Tier II", "Tier III"}
J.ENVOY_OPINION, J.ENVOY_SYMPATHY, J.ENVOY_SANCTION = 10, 10, 0
J.ANSWER_DESIRES = {PEACE = true, PROTECT = true, UNIFY = true}
J.MASTER_KNOWLEDGE = 0
J.MISSION_KNOWLEDGE = {CONFRONT = 6, REDEEM = 5, CLEANSE = 4, ENVOY = 2, MEDIATE = 1}
J.SEEK_KNOWLEDGE_CHANCE, J.SEEK_KNOWLEDGE = 15, {2, 4}
J.MEDITATE_KNOWLEDGE, J.MEDITATE_WEEKS = 8, 1
J.SEEK_COOLDOWN = 8
J.SEEK_COOLDOWN_FORCE = 0.3
J.FORCE_WORDS = {{80, "overwhelming"}, {60, "very strong"}, {40, "strong"}, {25, "stirring"}, {10, "present"},
                 {1, "faint"}, {0, "absent"}}
J.CLEANSE_SIDE, J.CLEANSE_DARKNESS = 30, 10
J.ODDS_WORDS = {{75, "promising"}, {55, "fair"}, {35, "uncertain"}, {0, "dangerous"}}
J.TRUST_SUCCESS, J.TRUST_FAILURE = 3, 4
J.MEDIATE_OPINION, J.MEDIATE_WEEKS, J.MEDIATE_ANGER = 15, 12, 4
J.PEACE_OPINION, J.PEACE_WEEKS, J.PEACE_INFLUENCE, J.PEACE_SYMPATHY = 10, 12, 2, 10

J.THREATS = {
    {key = "PROPHETS", name = "Kadann and the Prophets of the Dark Side", faction = "WARLORD_PROPHETS", units = {"KADANN", "KADANN_TEAM"}},
    {key = "LUMIYA", name = "Lumiya, the Dark Lady", faction = "WARLORD_LUMIYA", units = {"LUMIYA", "LUMIYA_TEAM"}},
    {key = "SHADOWSPAWN", name = "Shadowspawn and the Shadow Realm", faction = "WARLORD_SHADOWSPAWN", units = {"SHADOWSPAWN", "SHADOWSPAWN_TEAM"}},
    {key = "APPRENTICE", name = "The Dark Apprentice on Kamino", faction = "WARLORD_KAMINO", units = {"DARK_APPRENTICE", "DARK_APPRENTICE_TEAM"}},
    {key = "BRILL", name = "Foga Brill, the Inquisitor of Prakith", faction = "WARLORD_PRAKITH", units = {"FOGA_BRILL_TEAM", "FOGA_BRILL_TNT"}},
    {key = "CBAOTH", name = "Joruus C'baoth at Wayland", world = "WAYLAND", from = 9, to = 9, units = {"JORUUS_CBAOTH", "JORUUS_CBAOTH_TEAM"}},
    {key = "BYSS", name = "The reborn Emperor's Dark Jedi at Byss", world = "BYSS", from = 10, to = 10, lock = "IMPERIAL_DARK_JEDI_COMPANY"},
    {key = "NIGHTSISTERS", name = "The Nightsisters of Dathomir", world = "DATHOMIR"},
    {key = "EXAR_KUN", name = "The spirit of Exar Kun on Yavin", world = "YAVIN", chain = true},
}
J.LEAD_CHANCE, J.LEAD_SEEKER, J.LEAD_SANCTION, J.LEAD_MAX, J.LEAD_WEEKS = 40, 5, 5, 8, 15
J.LEAD_FROM = {"Luke", "a Master at the Temple", "a Delegate", "a senator's aide", "Republic Intelligence", "a trader's rumour"}
J.LEADS = {
    CHILD = {mission = "SEEK", title = "Someone gifted on {world}",
             texts = {"{who} hears of a child on {world} who knows what people will say before they say it.",
                      "A freighter pilot on {world} flies through asteroid fields with her eyes shut, and has for twenty years.",
                      "A young dockhand on {world} has never been hurt on a job where everyone else has.",
                      "An old card player on {world} is banned from every table in the city, and has never been caught cheating.",
                      "A teenage mechanic on {world} hears what is wrong with a hyperdrive before she opens it.",
                      "A widowed farmer on {world} always knows when the storms will come, to the hour.",
                      "A militia sergeant on {world} pulled his squad back a moment before the barracks fell in.",
                      "A medic on {world} writes of a child who heals birds with a touch.",
                      "On {world} a child walked out of a burning hangar without a mark, and will not say how.",
                      "A swoop racer's child on {world} has never lost a race, and has never seen the track.",
                      "Teachers on {world} write of a pupil who finds lost things before anyone says they are lost.",
                      "A child on {world} stopped a falling cargo crate with a scream, and a dozen dockworkers saw it."}},
    FAMILY = {mission = "SEEK", title = "A family of Force-users on {world}",
              texts = {"An old family on {world} has kept a gift from the Empire's notice for three generations.",
                       "{who} reports a family on {world} whose children all dream the same dreams.",
                       "A grandmother on {world} once served the old Order as a cook, and her grandchildren are strange.",
                       "Twins on {world} finish each other's sentences, and sometimes each other's thoughts."}},
    HERMIT = {mission = "SEEK", title = "An old Jedi in hiding on {world}",
              texts = {"Someone on {world} carries a lightsaber hilt and calls it a family heirloom.",
                       "{who} has heard of a hermit on {world} who survived the Purge and never stopped hiding.",
                       "An old healer on {world} hums the meditation chants of the old Temple without knowing why.",
                       "Spacers on {world} speak of a mechanic who fixes engines without opening them."}},
    REFUGEES = {mission = "SEEK", title = "Refugees who hear voices on {world}",
                texts = {"Among the refugees on {world} are some who hear voices no one else hears.",
                         "The camps on {world} are full of people the war has touched in strange ways.",
                         "A relief worker on {world} counts three refugees who knew the raid was coming before it came."}},
    NIGHTSISTER = {mission = "SEEK", title = "A witch who left her clan on {world}", dark = true,
                   texts = {"A young witch has broken with her clan on {world}, and is being hunted for it.",
                            "{who} hears of a girl on {world} who fled the Nightsisters with their spells in her head.",
                            "On {world} a witch of the Singing Mountain clans asks, through a trader, whether Luke's school takes outsiders."}},
    NAMED = {mission = "SEEK", title = "{jedi} on {world}",
             texts = {"{who} reports that {jedi} is on {world}, and may be ready to join the Order.",
                      "Word comes from {world}: {jedi} has been asking about Luke Skywalker's school.",
                      "{jedi} has been seen on {world}, and the Force is loud around them."}},
    UNREST = {mission = "MEDIATE", title = "Unrest on {world}",
              texts = {"Crowds fill the streets of {world}; its senator asks for someone who can talk to both sides.",
                       "{world}'s councils are deadlocked and the talk is of leaving the Republic.",
                       "Two clans on {world} have stopped speaking to each other, and the Republic's governor is caught between.",
                       "A strike has shut {world}'s spaceport, and both sides say they would talk to a Jedi."}},
    TURMOIL = {mission = "PEACE", title = "{world} near rising",
               texts = {"Riots on {world}: the garrison fears the worst within weeks.",
                        "{who} warns that {world} is one spark from open revolt.",
                        "Militias are arming on {world}, and no one remembers who fired first.",
                        "The Republic's offices on {world} were burned last night."}},
    RUINS = {mission = "LORE", title = "Ruins found on {world}",
             texts = {"Surveyors on {world} have found carved stone older than the Republic.",
                      "{who} brings a map that marks an old Jedi archive on {world}.",
                      "An antiquities dealer on {world} is selling pages of a Jedi journal, one at a time.",
                      "A quake on {world} opened a sealed vault beneath an old monastery."}},
    HOLOCRON = {mission = "LORE", title = "Luke senses a holocron on {world}", holocron = true,
                texts = {"Luke wakes before dawn: something old is calling from {world}.",
                         "In meditation Luke saw a glowing cube buried deep on {world}.",
                         "A voice that is not Ben's, nor Yoda's, whispers a name to Luke: {world}."}},
    THREAT = {mission = "CONFRONT", title = "Dark Jedi near {world}", dark = true,
              texts = {"{who} reports Dark Jedi moving openly near {world}: {threat}.",
                       "The Force is troubled around {world}: {threat} grows bolder.",
                       "Villages near {world} have emptied overnight. The survivors speak of {threat}.",
                       "A Republic patrol near {world} came back with its crew unable to remember the trip: {threat}."}},
    FALLEN = {mission = "REDEEM", title = "{jedi}'s presence felt on {world}",
              texts = {"Luke felt {jedi} for a moment, on {world}: alone, and not wholly lost.",
                       "{who} has seen {jedi} on {world}. They looked tired, not cruel.",
                       "A message reaches the Temple from {world}, unsigned, in {jedi}'s hand. It says only: not yet."}},
    DARK_SITE = {mission = "CLEANSE", title = "A dark site stirs on {world}", dark = true,
                 texts = {"Something on {world} that slept for a thousand years is waking.",
                          "The students' dreams all turn to {world} now, and none of them are good.",
                          "Birds no longer fly over the old ruins on {world}.",
                          "Pilgrims to {world} come back changed, angrier, and will not say what they saw."}},
    DISTURBANCE = {mission = "CLEANSE", title = "A Disturbance in the Force", dark = true, reveal = true,
                   texts = {"Luke feels a disturbance in the Force, centred on {world}, and cannot see its shape.",
                            "Every Master at the Temple has felt it: a shadow, gathering, and {world} at its heart."}},
}
J.LEAD_ORDER = {"CHILD", "FAMILY", "HERMIT", "REFUGEES", "NIGHTSISTER", "UNREST", "TURMOIL", "RUINS", "HOLOCRON",
                "THREAT", "FALLEN", "DARK_SITE"}
J.SEEK_FLOOR, J.SEEK_SIDE, J.FAMILY_CHANCE, J.HERMIT_CHANCE, J.REFUGEE_FORCE = 12, 20, 60, 70, 25
J.SEEK_STUDENT_SCALE, J.SEEK_MAX, J.SEEK_LEAD_EXTRA = 0.6, 30, 5
J.SEEK_LEAD_BAND, J.SEEK_LEAD_FORCE, J.SEEK_LEAD_PEOPLE, J.SEEK_LEAD_HERE = 35, 3, 35, 65
J.SEEK_WORDS = {{30, "Force: strong"}, {15, "Force: stirring"}, {8, "Force: faint"}, {0, "Force: quiet"}}
J.SEEK_LIGHT = {{"healer", "a healers' tradition the Empire never found: the people there think better of the Republic"},
                {"calm", "a place of deep calm: the Jedi comes home lighter in spirit"},
                {"echo", "an echo of the old Jedi in the stones: Knowledge +4"}}
J.SEEK_DARK = {{"presence", "a dark presence that watched them work"}, {"aspirant", "someone who wants to be a Dark Jedi"}}
J.SEEK_NONE = {"rumours, and nothing more", "a quiet world and kind people", "old stories of the Jedi, half remembered",
               "a fortune-teller who was a fraud, and knew it", "a shrine to the Jedi kept by people who never met one",
               "a child who was only lucky, as children are", "a long week of listening, and the Force silent"}
J.SEEK_LEAD_TEXTS = {"a rumour worth following", "a name, given in whispers", "an old story with a world in it",
                     "a trader who has seen something stranger elsewhere"}

J.CRAFTS = {{"XWING", 30, 0, "X-wing"}, {"AWING", 20, 0, "A-wing"}, {"Z95", 15, 0, "Z-95 Headhunter"}, {"YWING", 15, 0, "Y-wing"},
            {"EWING", 10, 10, "E-wing"}, {"BWING", 10, 0, "B-wing"}, {"R41", 8, 0, "R-41 Starchaser"},
            {"CLOAKSHAPE", 8, 0, "Cloakshape fighter"}, {"PREYBIRD", 5, 0, "Preybird"}}
J.Z95_EARLY = 30
J.HERO_CRAFT = {LUKE = "LUKE", CORRAN = "CORRAN", KYLE = "KYLE", MARA = "MARA"}
J.HERO_CRAFT_NAME = {LUKE = "X-wing", CORRAN = "X-wing", KYLE = "the Moldy Crow", MARA = "the Jade's Fire"}
J.DOWN_DEATH = 50

J.DARK_POWERS = {"WARLORD_PROPHETS", "WARLORD_LUMIYA", "WARLORD_SHADOWSPAWN", "WARLORD_KAMINO", "WARLORD_PRAKITH", "EMPIRE"}

J.TEACHING_COST = {20, 50, 100}
J.TEACHING_PATHS = {"GUARDIAN", "CONSULAR", "SEEKER"}
J.TEACHINGS = {
    GUARDIAN = {
        {name = "Forms of the Blade", text = "The old lightsaber forms, relearned: Jedi in battle (their craft and themselves) have 20% more health. Confront the Darkness +10%."},
        {name = "Shield of the Weak", text = "A member world with a Jedi in orbit raises 2 militia companies when an enemy fleet arrives (once in 10 weeks). Jedi craft +10% damage. Public Trust -5."},
        {name = "Jedi Commanders", text = "A Knight or Master can go with a fleet (Attach to a Fleet on their card): +10% damage to the forces with them in battle. Public Trust -5; their shadow rises a point a week while they serve."},
    },
    CONSULAR = {
        {name = "The Living Force", text = "Mediate and Keep the Peace +10%. The Order's darkness fades a point a week faster."},
        {name = "Hands That Heal", text = "The wounded return in half the time, and a failed mission of tier I or II never kills. Public Trust gains are half as large again."},
        {name = "Jedi Ambassadors", text = "Every foreign power thinks better of the Republic (+10). An Envoy who succeeds at a power's capital also lets you offer it a treaty without a Senate mandate (a ceasefire, or an alliance in peace)."},
    },
    SEEKER = {
        {name = "The Long Memory", text = "Seek the Force and Recover the Lore +10%. Leads come a quarter more often."},
        {name = "Many Hands", text = "Training XP comes a quarter faster, the Temple has room for 10 Initiates, and students on missions earn three times the XP."},
        {name = "The Great Holocron", text = "Once a year the Holocron can raise an Initiate straight to Knight. Knowledge +2 a week. Every Jedi's shadow is shown on their card."},
    },
}

J.CHARTER_JEDI = 8
J.CHARTER = {
    {key = "ORDERS", name = "Politics",
     text = "Who may tell the Jedi what to do. The answer is permanent.",
     a = {key = "SENATE", name = "Answer to the Senate",
          text = "Mandate +5 now, and upkeep is halved. The Chancellor will ask for a Jedi from time to time, and the politics raise the shadow of Jedi sent on missions."},
     b = {key = "APART", name = "Stand Apart",
          text = "No one orders the Jedi. Autonomy-minded worlds +10, security-minded worlds -10. Upkeep is doubled unless the Senate has funded the Order in the last year: a yearly fight in the chamber."}},
    {key = "ATTACH", name = "Attachments",
     text = "May a Jedi love, marry, have a family? The answer is permanent.",
     a = {key = "OLD", name = "The Old Code",
          text = "Grief raises the shadow half as much. Seek the Force finds fewer students (-10%)."},
     b = {key = "LUKE", name = "Luke's Way",
          text = "Seek the Force finds more students (+15%). A Jedi's death weighs half as heavily again on those close to them."}},
    {key = "DARK", name = "Dark Knowledge",
     text = "What to do with the Sith lore the Jedi find. The answer is permanent.",
     a = {key = "DESTROY", name = "Destroy It",
          text = "Dark sites raise no shadow. Recover the Lore brings a quarter less Knowledge."},
     b = {key = "STUDY", name = "Study It",
          text = "Recover the Lore brings half as much Knowledge again. Dark sites raise the shadow by more, and Sentinels' shadow creeps up."}},
}

J.SEATS = {
    {key = "GRAND", name = "Grand Master", text = "Leads the Order and senses darkness in the Jedi at the Temple. Meditate on the Force (a lead) and, once in 26 weeks, Seek a Vision of one Jedi (their darkness and potential laid bare, and a glimpse: a lead, a warning that lifts their shadow, or a lesson)."},
    {key = "TRAINING", name = "Master of the Path", path = "GUARDIAN", text = "Training XP +25%; a Knight's trial needs one mission fewer; room for 2 more Initiates, and those they prepare start as Padawans at 20 XP. Sets the Temple's Regimen."},
    {key = "DIPLOMACY", name = "Keeper of the Accord", path = "CONSULAR", text = "Mediate, Keep the Peace, Answer a Call and Envoy +10%. With the Jedi Sanction Act, posts Knights as standing envoys (Envoy Corps)."},
    {key = "LORE", name = "Master of the Archives", path = "CONSULAR", text = "Keeps the Reliquary: researches its artifacts, and only with a Master of the Archives do their effects work. Knowledge +1 a week, more for each artifact fully researched."},
    {key = "GUARDIANS", name = "Master of Guardians", path = "GUARDIAN", text = "Confront and Cleanse +10%; Jedi struck down die a quarter less often. Declares the Hunt on a dark threat or a fallen Jedi, and posts Knights to it."},
    {key = "HEALING", name = "Master of the Living Force", path = "SEEKER", text = "The wounded heal 40% faster; Counsel lifts 5 more; senses darkness in the Jedi at the Temple. Once in 20 weeks, a Healing Trance heals one Jedi at once and lifts their shadow."},
    {key = "WATCH", name = "Watchman of the Order", path = "SEEKER", text = "Posts Knights as Watchmen to worlds, each watching its sector: leads there come twice as often and warn before they lapse. Senses darkness from 30, in Jedi home or away."},
}
J.SEAT_ORDER = {"GRAND", "TRAINING", "DIPLOMACY", "LORE", "GUARDIANS", "HEALING", "WATCH"}
J.REGIMENS = {
    FORMS = {name = "Forms", text = "Lightsaber forms day and night: Training XP +25%, but sparring wounds a student now and then.", xp = 1.25, wound = 4},
    MEDITATION = {name = "Meditation", text = "Long meditations: students' shadow -1 a week, Training XP -10%.", xp = 0.9, shadow = -1},
    STUDY = {name = "Study", text = "The archives and the old texts: Knowledge +1 a week, Training XP -10%.", xp = 0.9, knowledge = 1},
}
J.REGIMEN_ORDER = {"FORMS", "MEDITATION", "STUDY"}
J.POSTS = {ENVOY = 2, HUNT = 2, WATCH = 5}
J.ENVOY_WORLD_MAX, J.ENVOY_COURT_EVERY, J.ENVOY_TRUST_EVERY = 15, 2, 2
J.HUNT_RATE, J.HUNT_MAX = 2, 20
J.WATCH_LEAD_CHANCE, J.WATCH_WARN = 20, 5
J.VISION_EVERY, J.TRANCE_EVERY = 26, 20
J.VISION_GLOBAL = 5
J.SECOND_TRAIT = 40
J.TRAINING_INITIATES, J.TRAINING_START_XP = 2, 20
J.HEALING_HEAL, J.HEALING_COUNSEL, J.GUARDIAN_DEATH = 0.6, 5, 0.75
J.WATCH_SENSE = 30
J.FOUND_NATIVE = 70
J.HUMAN_FEMALE = {"Asyr", "Dalia", "Halia", "Ilsa", "Kessa", "Mirel", "Nessa", "Rhea", "Talya", "Vena", "Wynn", "Yara",
                  "Seryn", "Leesha", "Brielle", "Tamsin", "Corra", "Elin", "Anya", "Brisa", "Calla", "Delis", "Ember",
                  "Fia", "Galene", "Hesta", "Irisa", "Jessa", "Kira", "Liane", "Maera", "Nyra", "Oriel", "Pira", "Risa",
                  "Sabeth", "Tova", "Ursa", "Vesna", "Zhana", "Alys", "Bryn", "Cela", "Dorae", "Elsa", "Isolde", "Jinn",
                  "Lena", "Moriah", "Petra", "Selka", "Thea"}
J.HUMAN_MALE = {"Bren", "Corwin", "Ereth", "Fenn", "Garen", "Joren", "Lorn", "Orin", "Pell", "Quill", "Soren", "Ulric",
                "Zev", "Dace", "Torin", "Halvar", "Kaed", "Merrin", "Arlen", "Bastan", "Cade", "Daven", "Emrys", "Falk",
                "Gideon", "Hollis", "Ivar", "Jace", "Kellan", "Lucan", "Marek", "Niall", "Oswin", "Pax", "Rane", "Sten",
                "Tarek", "Ulf", "Varian", "Wes", "Yorick", "Aldo", "Brannoc", "Cass", "Dorn", "Evander", "Jory",
                "Lennick", "Mattias", "Rowan", "Tobin", "Vance"}

J.CRISES = {
    PURPOSE = {title = "The Jedi's Purpose", text = "The Senate asks what the Jedi are for: the Republic's protectors, or the Force's servants?",
               a = {label = "Protectors", text = "The Jedi stand for the Republic", trust = 6, mandate = 2, shadow = 3},
               b = {label = "Servants", text = "The Jedi serve the Force first", trust = -3, knowledge = 6}},
    COMMISSIONS = {title = "Should Jedi Hold Commissions?", text = "The Fleet offers a Guardian a command. Admirals are delighted; many senators are not.",
                   a = {label = "Accept", text = "A Jedi takes a commission", trust = -5, interest = {"Security", 8}, shadow = 4},
                   b = {label = "Decline", text = "The Jedi decline the Fleet's offer", trust = 3, interest = {"Security", -4}}},
    RIOTS = {title = "Anti-Jedi Riots", text = "Worlds raised on Palpatine's stories riot against the 'sorcerers'. The Temple's envoys ask to be heard.",
             a = {label = "Send envoys", text = "Jedi go among the rioters unarmed", trust = 8, shadow = 2},
             b = {label = "Stay silent", text = "The Order waits for it to pass", trust = -8}},
    ACCUSED = {title = "A Jedi Accused", text = "A senator charges a Jedi with misusing the Force on a witness. The chamber wants an answer.",
               a = {label = "Stand by them", text = "The Order stands by its own", trust = -5, mandate = -2, shadow = -2},
               b = {label = "Open an inquiry", text = "The Order opens its doors to the Senate", trust = 5, shadow = 3}},
    WHO_LEADS = {title = "Who Leads Now?", text = "Luke Skywalker is gone. The Order must choose whether its most senior Master leads alone, or the Masters together.",
                 a = {label = "One leader", text = "The senior Master takes up Luke's title", trust = 3, shadow = 3},
                 b = {label = "The Masters", text = "The Masters lead together", knowledge = 5}},
    STUDENT_ASKS = {title = "A Student Asks About the Temple", text = "A student has been dreaming of the old Massassi temple on Yavin, and of a voice in it.",
                    a = {label = "Forbid it", text = "The students are forbidden the old temple", shadow = -5, knowledge = -3, ends_chain = true},
                    b = {label = "Let them look", text = "A student goes to the old temple alone", knowledge = 8, shadow = 6, chain = true}},
    STRUCK_DOWN = {title = "Luke Is Struck Down", text = "Exar Kun's spirit has turned the students on their Master: Luke lies between life and death, and cannot teach.",
                   a = {label = "Keep vigil", text = "The students gather around him and hold on", trust = -5, shadow = -4},
                   b = {label = "Tell no one", text = "The Temple keeps its secret, and fear grows", shadow = 8}},
    SENATE_ASKS = {title = "The Chancellor Asks", text = "Under the Charter, the Chancellor asks that a Jedi go to the unhappiest of the member worlds.",
                   a = {label = "Send a Jedi", text = "A free Jedi goes at once", trust = 2, mandate = 2, order_mission = true},
                   b = {label = "Refuse", text = "The Order refuses the Chancellor", trust = -2, mandate = -4}},
    COUNCIL = {title = "A Council of Masters?", text = "The Masters ask for a Council. Luke has resisted the idea: he remembers what the last one missed.",
               a = {label = "Seat a Council", text = "A Jedi Council is seated", trust = 3, opens_council = true},
               b = {label = "Not yet", text = "Luke asks them to wait", shadow = 2}},
}
J.DARK_EVENTS = {
    RAGE = {title = "{name}'s Rage", text = "A practice duel went too far: {name} did not stop when the other student fell.",
            a = {label = "Discipline them", text = "{name} is disciplined before the Order", pshadow = -10, pxp = -20},
            b = {label = "Let it pass", text = "The duel is forgotten, officially", pshadow = 8, fall = true}},
    WHISPER = {title = "A Whisper in the Dark", text = "{name} has been hearing a woman's voice in meditation. She says they are wasted on Luke's school.", threat = "LUMIYA",
               a = {label = "Tell their Master", text = "{name} tells their Master everything", pshadow = -5, watch = true},
               b = {label = "Keep it secret", text = "{name} keeps the voice to themselves", pshadow = 12, fall = true}},
    ENVOY = {title = "The Prophets' Envoy", text = "A robed stranger at the Temple's edge offers {name} the 'true path' of the Prophets of the Dark Side.", threat = "PROPHETS",
             a = {label = "Turn them away", text = "The envoy is sent away", pshadow = -5, trust = 2},
             b = {label = "Let them listen", text = "{name} listens, and learns", knowledge = 6, pshadow = 15, fall = true}},
    POWER = {title = "Dreams of Power", text = "Passed over, {name} dreams of a power that would make the Masters listen.",
             a = {label = "Speak with them", text = "A Master sits with {name} through the night", pshadow = -8},
             b = {label = "Give them a task", text = "{name} is given work to prove themselves", pshadow = 4, pxp = 20}},
    CALLS = {title = "The Dark Side Calls", text = "Grief has hollowed {name} out, and something is filling the space.",
             a = {label = "Mourn together", text = "The Temple mourns with {name}", pshadow = -10, close = -5},
             b = {label = "Carry on", text = "{name} carries on as if nothing were wrong", pshadow = 8, fall = true}},
    HOLOCRON = {title = "A Sith Holocron", text = "{name} has brought back a Sith holocron from a dark site. It whispers.",
                a = {label = "Destroy it", text = "The holocron is destroyed", darkness = -3},
                b = {label = "Study it", text = "The Order studies the holocron", knowledge = 15, darkness = 8, pshadow = 8}},
    VISION = {title = "A Vision", text = "{name} has seen the future in meditation: someone they love, dying. They want to stop it, whatever it takes.",
              a = {label = "Teach acceptance", text = "{name} learns that visions are not orders", pshadow = -8, pxp = 10},
              b = {label = "Let them act", text = "{name} sets out to change what they saw", pshadow = 12, fall = true}},
    RIVAL = {title = "A Rival's Triumph", text = "Another student bested {name} before the whole Temple, and {name} has not forgiven it.",
             a = {label = "Make them spar again", text = "The two spar again, under a Master's eye", pshadow = -6},
             b = {label = "Separate them", text = "The rivals are kept apart", pshadow = 5}},
    AMULET = {title = "A Sith Amulet", text = "{name} came back from a mission with a black stone amulet, and will not take it off.",
              a = {label = "Take it from them", text = "The amulet is taken and sealed away", pshadow = -5, darkness = -2},
              b = {label = "Let them keep it", text = "{name} keeps the amulet", pshadow = 15, knowledge = 4, fall = true}},
    HATRED = {title = "Hatred for the Empire", text = "{name} lost a home to the Empire, and lately speaks of Imperials as things, not people.",
              a = {label = "Send them to heal", text = "{name} works among wounded prisoners of war", pshadow = -10, trust = 2},
              b = {label = "Point them at the war", text = "{name}'s anger is aimed at the enemy", pshadow = 10, pxp = 15}},
    DOUBT = {title = "Doubt", text = "{name} has stopped believing the Order can stand against what is coming.",
             a = {label = "Remind them why", text = "Luke tells {name} of Dagobah, and of his own doubts", pshadow = -6},
             b = {label = "Let them find faith alone", text = "{name} is left with their doubts", pshadow = 6}},
    BRAKISS = {title = "Brakiss's Secret", text = "Luke has seen through {name}: an Imperial agent, sent to learn the Jedi's ways.",
               a = {label = "Expel him", text = "{name} is sent away, and goes to the Empire", expel = true},
               b = {label = "Try to redeem him", text = "Luke tries to reach the man behind the mask", redeem_spy = true}},
}
J.REDEEM_SPY = 30
J.CRISES.SENATOR_CHILD = {title = "A Senator's Child", text = "A senator's daughter has the gift. Her father wants her trained, and wants the Order to remember who asked.",
    a = {label = "Take her", text = "The girl comes to the Temple", student = true, mandate = 2, trust = -2},
    b = {label = "Refuse the favour", text = "The Order will not be owed", trust = 3, mandate = -2}}
J.CRISES.DOCUMENTARY = {title = "The HoloNet Wants a Story", text = "A HoloNet crew asks to film a year at the Temple.",
    a = {label = "Open the doors", text = "The galaxy watches the Jedi train", trust = 8, shadow = 2},
    b = {label = "Keep them out", text = "The Temple stays closed to cameras", trust = -2}}
J.CRISES.SMUGGLER = {title = "A Smuggler's Holocron", text = "A smuggler offers a holocron 'from a Sith tomb', for 2000 credits and no questions.",
    a = {label = "Buy it", text = "The Order pays the smuggler", credits = -2000, knowledge = 12, darkness = 3},
    b = {label = "Send him away", text = "The smuggler leaves with his prize", knowledge = 0}}
J.CRISES.CANTINA = {title = "A Jedi in the Cantina", text = "A Knight used the Force in a cantina brawl. The footage is everywhere.",
    a = {label = "Apologise publicly", text = "The Order apologises", trust = -2, shadow = -2},
    b = {label = "Defend the Knight", text = "The Order says the Knight saved lives", trust = -5, shadow = 2}}
J.CRISES.PILGRIMS = {title = "Pilgrims at the Temple", text = "Thousands have come to Yavin to see the Jedi. They camp in the jungle, and some are sick.",
    a = {label = "Welcome them", text = "The Temple's healers tend the pilgrims", trust = 6, knowledge = -2},
    b = {label = "Turn them back", text = "The pilgrims are sent home", trust = -4}}
J.CRISES.LIGHTSABER = {title = "An Old Jedi's Lightsaber", text = "A family has brought the lightsaber of a Jedi who died in the Purge. They want it honoured, or returned.",
    a = {label = "Study it", text = "The Order studies the old weapon", knowledge = 6},
    b = {label = "Lay it to rest", text = "The lightsaber is laid in the Temple's hall of memory", trust = 4, shadow = -2}}
J.CRISES.ARTIST = {title = "The Sculptor's Request", text = "A famous sculptor asks to carve the new Order into the Temple's walls.",
    a = {label = "Let him carve", text = "The new Order is carved in stone", trust = 3, shadow = -1},
    b = {label = "No monuments", text = "The Jedi want no monuments", knowledge = 2}}
J.CRISES.TRADERS = {title = "Traders at Yavin", text = "Merchants want to open a market at the Temple's landing field.",
    a = {label = "Allow it", text = "A market grows at the Temple's edge", credits = 600, shadow = 2},
    b = {label = "Keep the Temple quiet", text = "The landing field stays quiet", shadow = -1}}
J.CRISIS_ORDER = {"PURPOSE", "COMMISSIONS", "RIOTS", "ACCUSED", "SENATOR_CHILD", "DOCUMENTARY", "SMUGGLER", "CANTINA",
                  "PILGRIMS", "LIGHTSABER", "ARTIST", "TRADERS"}

J.SIGNS = {"{name} speaks of the old Sith with too much interest.", "{name} has stopped sleeping, and will not say why.",
           "{name} grows short with the students.", "{name} won a duel in practice, and did not stop at once.",
           "{name} says the Order is too careful for the times."}
J.MOODS = {"{name} is at peace.", "{name} meditates in the old temple's shade.", "{name} is restless, and wants to be of use."}
J.MOODS_RANK = {
    {"{name} sweeps the temple steps, and is not sure why.", "{name} watches the Padawans spar, wide-eyed.",
     "{name} is learning to sit still for an hour. It is not going well.", "{name} writes home, and tears it up.",
     "{name} asks the older students too many questions."},
    {"{name} practises the forms until their arms ache.", "{name} runs the jungle paths at dawn.",
     "{name} is learning to lift stones without looking at them.", "{name} carries their Master's books, and reads them.",
     "{name} builds and rebuilds a training remote.", "{name} spars with the other Padawans."},
    {"{name} drills the Padawans in the forms.", "{name} repairs the Temple's old shuttles.",
     "{name} studies star charts of the Outer Rim.", "{name} meditates in the great hall.",
     "{name} is waiting, restlessly, for a mission.", "{name} tunes their lightsaber's crystal."},
    {"{name} teaches the students to listen to the Force.", "{name} meditates at the top of the Temple.",
     "{name} studies the old holocrons late into the night.", "{name} walks the jungle alone, thinking.",
     "{name} counsels a troubled student.", "{name} writes down what they remember of the old Order."},
    {"{name} watches over the whole Temple.", "{name} meditates on the Order's future.",
     "{name} speaks with each Master in turn.", "{name} answers letters from the Senate, patiently."},
}
J.MOODS_TRAIT = {
    COMPASSIONATE = {"{name} tends the sick in the settlement below the Temple.", "{name} looks after the newest Initiates."},
    DISCIPLINED = {"{name} keeps to their routine to the minute.", "{name} runs the forms a hundred times before breakfast."},
    RECKLESS = {"{name} took a shuttle out without asking, again.", "{name} climbed the Temple's outer wall for a bet."},
    PROUD = {"{name} wants everyone to know of their last mission.", "{name} corrects the others' forms, uninvited."},
    GRIEVING = {"{name} sits by the memorial stones.", "{name} keeps to themselves."},
    SCHOLAR = {"{name} has not left the archives in days.", "{name} is translating an old text."},
    PEACEMAKER = {"{name} settles a quarrel between two students.", "{name} writes to old friends in the Senate."},
    DUELLIST = {"{name} duels anyone who will face them.", "{name} invents a new kata."},
    TEACHER = {"{name} has gathered the youngest for a lesson.", "{name} is patient with the students."},
    EMOTIONAL = {"{name} laughs too loudly, and weeps too easily.", "{name} took a slight to heart."},
    COMPETITIVE = {"{name} keeps score of everyone's missions.", "{name} challenged a Knight to a race through the jungle."},
    PATIENT = {"{name} waits for the Force to show them the way.", "{name} spends the day tending one plant."},
    INTUITIVE = {"{name} feels something coming, and cannot name it.", "{name} knows who is at the door before they knock."},
}

return J
