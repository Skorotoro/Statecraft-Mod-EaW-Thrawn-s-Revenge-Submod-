local C = {}

C.FACTION = "EMPIRE"
C.WEEK_SECONDS = 40
C.SETUP_AFTER = 40
C.PANEL_DELAY_MS = 900
C.REGIME_WAIT = 90
C.NEW_CAMPAIGN = 35

C.AUTHORITY = {START = 40, WEEK = 4, MAX = 100}

C.SHIPS = {ENABLED = true, SPAWN_PER_WEEK = 2, ESCAPE = 60, SENT_WEEKS = 2, SENT_OPINION = -8, SENT_FADE = 12}

C.PROFILES = {
    LAMBDA_SECTOR = {regime = "LAMBDA", grand_moffs = false, succession = false, legitimacy_race = false,
                     focus = "Hold the Lambda Sector together and watch your neighbours."},
}
C.MOFF_BEFORE_BREAKAWAY = 2
C.EARLY_YEAR = 6

C.ADMIRALTY_ORDER = {"grand_admiral", "admiral", "captain"}
C.FLEET_COOLDOWN = 10
C.ADMIRALTY = {
    grand_admiral = {name = "Grand Admiral", seats = 2, pool = "G", cost = 30, from = "admiral", titles = {"grand_moff"},
                     power = 4, stability = 2, opinion = 30,
                     desc = "Commands a whole fleet. Raised from the Admirals, or a Grand Moff."},
    admiral = {name = "Admiral", seats = 2, per_skill = 25, pool = "M", cost = 12, from = "captain", titles = {"moff", "grand_moff"},
               power = 2, stability = 1, opinion = 20,
               desc = "Commands a battle group from a Star Destroyer. Raised from the Captains, or a Moff or Grand Moff."},
    captain = {name = "Captain", seats = 4, per_skill = 15, pool = "V", cost = 6, power = 1, stability = 0, opinion = 12,
               desc = "Commands a cruiser and its escorts."},
}

C.TITLES = {
    grand_moff = {name = "Grand Moff", rank = 3, influence = 5, power_seat = 4},
    moff = {name = "Moff", rank = 2, influence = 3, power_seat = 3},
    governor = {name = "Governor", rank = 1, influence = 1, power_seat = 1},
    courtier = {name = "Courtier", rank = 0, influence = 0, power_seat = 0},
}
C.COMMANDER = {name = "Commander", rank = 1}
C.LORD = {name = "Lord", classes = {DARK_JEDI = true, DARK_LADY = true, DARK_ADEPT = true, LORD = true, PROPHET = true,
          PROPHET_FALSE = true, INQUISITOR_HIGH = true, EXECUTOR = true}, names = {Cronal = true}}
C.SECTOR_GEO = {JOIN = 130, LINK = 90}
C.MIN_SECTOR_WORLDS = 3
C.GROW_JUMPS = 2
C.MIN_OVERSECTOR = 2
C.PROCLAIM = {WORLDS = 3, AUTHORITY = 25, CREDITS = 2000}

C.VACANT = {VALUE_STEP = 400, WEEKS_STEP = 8, WEEKS_CAP = 24, FULL = 1.5, STABILITY_CAP = 12, LOYALTY_CAP = 5,
            APPOINT = 3}

C.RAISE = {AUTHORITY = 5, OPINION = -5, WEEKS = 10, COOLDOWN = 2}

C.DEATH = {STABILITY = 2, PER_POWER = 0.5, STABILITY_CAP = 10}
C.CONQUERED = {STABILITY = 1, HOLDER = -15, TITLELESS = -25, WEEKS = 16, MOFF = -6}
C.REBELLION = {STABILITY = 3, LEGITIMACY = -3}

C.LEGITIMACY = {FEALTY = 6, ABSORBED = 12, REGIME_CHANGE = -15, OUTPACED = 6}

C.TRAITOR = {OPINION = -8, STABILITY = 2, APPOINTED = -12, LOYALTY = -15}

C.DISTANCE = {FREE_JUMPS = 3, PER_JUMP = 1.5, CAP = 9}
C.OVERSECTOR_NAMES = {
    ["Deep Core"] = "Deep Core Security Zone", ["Core Worlds"] = "Core Oversector", ["Colonies"] = "Colonies Oversector",
    ["Inner Rim"] = "Inner Rim Oversector", ["Expansion Region"] = "Expansion Oversector",
    ["Mid Rim"] = "Mid Rim Oversector", ["Outer Rim"] = "Oversector Outer", ["Hutt Space"] = "Hutt Space Protectorate",
    ["Unknown Regions"] = "Unknown Regions Command",
}
C.PROCLAIM_NAMES = {"Abrion", "Bheriz", "Cadinth", "Dalchon", "Ekibi", "Faos", "Glythe", "Harrin", "Iskar",
                    "Jaminere", "Kanchen", "Lazerian", "Mortex", "Nilgaard", "Oovo", "Parmic", "Quellor", "Rachuk",
                    "Shapani", "Tarabba", "Ulmatra", "Vorzyd", "Wornal", "Xaxis", "Yarith", "Zuma"}

C.LOYALTY = {
    START_MIN = -8, START_MAX = 8,
    RATE = 0.35, STEP = 1, STABILITY_RATE = 0.22,
    BASE = 50,
    ISOLATED = 12,
    ISOLATED_SOME = 5,
    LEGITIMACY = 0.4,
    STABILITY = 0.3,
    AMBITION = 0.2,
    POWER_FROM = 4,
    POWER_PER = 1.2, POWER_CAP = 14,
    POWER_NATURE = {ambitious = 1.5, schemer = 1.3, corrupt = 1.2, paranoid = 1.1, pragmatist = 0.6,
                    administrator = 0.8, loyalist = 0.2},
    MINDER = -8,
}
C.OPINION = {
    GRANTED_TITLE = 25, GRANTED_OFFICE = 20, HONOURED = 15, REVOKED = -40, FIRED = -25, TRIBUTE = -18, TRIBUTE_PEERS = -3,
    REFUSED = -10, PETITION_GRANTED = 15, RIVAL_REWARDED = -10, FRIEND_PUNISHED = -10, CONCESSION = 15,
    BACKED_WINNER = 20, OPPOSED_REGIME = -15, NEW_MASTER = -10, LEAVING = -40, RECOGNISED = 55, PASSED_OVER = -8,
    REPLACED = -10,
}

C.TIES = {
    MAX = 3,
    START_RANDOM = 50,
    WEEKLY = 1,
    LORE_RIVALS = {
        {"Sate Pestage", "Ysanne Isard"}, {"Sate Pestage", "Carnor Jax"}, {"Sate Pestage", "Bertroff Hissa"},
        {"Ysanne Isard", "Fliry Vorru"}, {"Ysanne Isard", "Carnor Jax"}, {"Carnor Jax", "Kadann"},
        {"Natasi Daala", "Blitzer Harrsk"}, {"Vilim Disra", "Gilad Pellaeon"}, {"Blitzer Harrsk", "Malfkla Yzu"},
    },
    LORE_FRIENDS = {
        {"Thrawn", "Gilad Pellaeon"}, {"Vilim Disra", "Grodin Tierce"}, {"Vilim Disra", "Grodin Tierce & Flim"},
        {"Ysanne Isard", "Delak Krennel"}, {"Natasi Daala", "Gilad Pellaeon"}, {"Gilad Pellaeon", "Teren Rogriss"},
        {"Maximilian Veers", "Anderton Kloff"},
    },
}

C.LIFE = {WEEK_CHANCE = 70, COUNT = {70, 22, 8}, GOVERNOR = 1.5, SECTOR = 6, LIEGE = 3, PEER = 1, OTHER = 0.3,
          KINDS = {faction = 16, introduce = 16, turn = 16, sway = 14, friends = 16, rivals = 22},
          SWAY_SHARE = 0.3, SWAY_CAP = 8, SWAY_WEEKS = 10, SWAY_FACTION = 25, VASSAL = 5}

C.FIEF = {GRACE = 8, GROW = 12, PER_RANK = 5, WANT = {captain = 1, admiral = 2, grand_admiral = 3},
          HELD = {governor = 1, moff = 2, grand_moff = 3},
          NATURE = {corrupt = 1.6, ambitious = 1.5, schemer = 1.3, paranoid = 1.1, pragmatist = 0.7, administrator = 0.8,
                    loyalist = 0.25}}

C.UNREST = {BELOW = 20, DEEP = 10, STEP = 4, CAP = 4}
C.WORLD_VALUE = {INCOME = 0.5, MIN = 0.3, MAX = 4}
C.HOLD = {GOVERNOR = 3, MOFF = 1, CAP = 15, FADE = 1, UNREST = 1, UNREST_CAP = -10, RECOVER = 1}
C.RELIEF = {WEEKS = 8, LOYALTY = 6, STABILITY = 8}
C.REVOLT_BELOW = 4

C.REVENUE = {NO_GOVERNOR = 50, NO_MOFF = 25, MAX = 10, HIGH = 50, LOW = 40}
C.UNGOVERNED = {BELOW = 60, CHANCE = 10, STEEP = 30, NO_PALACE = 2, AFTER_CONQUEST = 3, AFTER_RISING = 2,
                AFTER_GOVERNOR = 2,
                PALACES = {"EMPIRE_OFFICE", "PENTASTAR_OFFICE", "MALDROOD_OFFICE", "ERIADU_OFFICE", "ZSINJ_OFFICE",
                           "KAMINO_OFFICE", "IMPERIAL_PROTEUS_OFFICE", "EMPIRE_CAPITAL", "IMPERIAL_PROTEUS_CAPITAL"}}

C.LORE_TRAITS = {
    ["Sate Pestage"] = {"schemer", "administrator"}, ["Ysanne Isard"] = {"schemer", "paranoid", "tarkinist"},
    ["Thrawn"] = {"navy", "pragmatist"}, ["Gilad Pellaeon"] = {"navy", "loyalist", "pragmatist"},
    ["Natasi Daala"] = {"navy", "ambitious", "tarkinist"}, ["Carnor Jax"] = {"ambitious", "schemer", "palpatine"},
    ["Vilim Disra"] = {"schemer", "corrupt", "xenophobe"}, ["Grodin Tierce"] = {"army", "palpatine"},
    ["Grodin Tierce & Flim"] = {"schemer", "palpatine"}, ["Blitzer Harrsk"] = {"navy", "ambitious"},
    ["Treuten Teradoc"] = {"navy", "corrupt", "ambitious"}, ["Kosh Teradoc"] = {"navy", "ambitious"},
    ["Ardus Kaine"] = {"administrator", "ambitious"}, ["Delak Krennel"] = {"ambitious", "navy", "xenophobe"},
    ["Bertroff Hissa"] = {"palpatine", "schemer"}, ["Fliry Vorru"] = {"corrupt", "schemer"},
    ["Kadann"] = {"palpatine", "paranoid"}, ["Ulric Tagge"] = {"ambitious", "army"},
    ["Teren Rogriss"] = {"navy", "loyalist"}, ["Maximilian Veers"] = {"army", "loyalist"},
    ["Anderton Kloff"] = {"army", "tarkinist"}, ["Malfkla Yzu"] = {"navy", "ambitious"},
    ["Quarsh Panaka"] = {"administrator", "loyalist"}, ["Lumiya"] = {"schemer", "palpatine"},
    ["Zsinj"] = {"ambitious", "schemer", "navy"}, ["Denn Wessex"] = {"ambitious", "tarkinist"},
    ["Lynch Hauser"] = {"ambitious", "administrator"}, ["Nile Owen"] = {"ambitious"},
    ["Tol Getelles"] = {"administrator", "tarkinist"}, ["Cronal"] = {"schemer", "ambitious", "paranoid"},
    ["Wilek Nereus"] = {"corrupt", "xenophobe"}, ["Bal Jaset"] = {"schemer", "palpatine"},
    ["Voss Parck"] = {"navy", "thrawn", "loyalist"}, ["Dagon Niriz"] = {"navy", "thrawn"},
    ["Gaen Drommel"] = {"navy", "ambitious"}, ["Uther Kermen"] = {"navy", "ambitious"},
    ["Utoxx Prentioch"] = {"ambitious", "administrator"}, ["Gronn"] = {"ambitious"},
    ["Sander Delvardus"] = {"army", "ambitious"}, ["Malcor Brashin"] = {"army", "palpatine"},
    ["Soontir Fel"] = {"navy", "pragmatist"}, ["Turr Phennir"] = {"navy", "ambitious"},
    ["Joruus C'baoth"] = {"ambitious", "paranoid"}, ["Sedriss QL"] = {"palpatine", "army"},
    ["Tol Sivron"] = {"corrupt", "administrator"}, ["Umak Leth"] = {"administrator", "palpatine"},
    ["Pter Thanas"] = {"navy", "pragmatist"}, ["Iolan Gendarr"] = {"navy", "loyalist"},
}

C.TRAITS = {
    loyalist = {name = "Loyalist", loyalty = 15, ambition = -15, desc = "Serves the throne, whoever sits on it."},
    ambitious = {name = "Ambitious", loyalty = -5, ambition = 25, desc = "Wants more, and asks for it."},
    corrupt = {name = "Corrupt", loyalty = -3, influence = 2, skill = {TREASURY = -25}, income = -5,
               desc = "Takes a cut of everything that passes through their hands."},
    tarkinist = {name = "Tarkinist", likes = {ISARD = 10, PALPATINE = 10}, dislikes = {PELLAEON = 10, DAALA = 5},
                 desc = "Believes in rule through the fear of force."},
    navy = {name = "Navy man", skill = {FLEET = 25}, power = 2, desc = "A career naval officer."},
    army = {name = "Army man", skill = {ARMY = 25}, power = 1, desc = "Rose through the Imperial Army."},
    xenophobe = {name = "Xenophobe", dislikes = {THRAWN = 20}, desc = "Will not bow to an alien."},
    pragmatist = {name = "Pragmatist", likes = {PELLAEON = 5, DAALA = 5}, regime_change = 0.5,
                  desc = "Accepts whoever keeps the Empire standing."},
    palpatine = {name = "Palpatine loyalist", likes = {PALPATINE = 20}, desc = "Waits for the Emperor's return."},
    thrawn = {name = "Thrawn admirer", likes = {THRAWN = 15}, desc = "Sees in Thrawn the Empire's last genius."},
    schemer = {name = "Schemer", loyalty = -5, skill = {INTEL = 20, VIZIER = 10}, plots = 1.5,
               desc = "Every alliance is a step towards the next betrayal."},
    administrator = {name = "Administrator", skill = {TREASURY = 20, VIZIER = 15}, stability = 1, income = 5,
                     desc = "Keeps the sector's ledgers and its people in order."},
    paranoid = {name = "Paranoid", loyalty = -5, minder_ok = true, skill = {INTEL = 10},
                desc = "Trusts no one; a minder only confirms it."},
    integrated = {name = "Integrated", loyalty = -10, fades = true, desc = "A former rival, newly sworn to the throne."},
}
C.TRAIT_ODDS = {"loyalist", "ambitious", "corrupt", "tarkinist", "navy", "army", "xenophobe", "pragmatist",
                "palpatine", "thrawn", "schemer", "administrator", "paranoid"}
C.TRAIT_SUCCESSOR = {tarkinist = "ISARD", thrawn = "THRAWN", palpatine = "PALPATINE", pragmatist = "PELLAEON",
                     xenophobe = "CCOGM"}

C.OFFICE_ORDER = {"VIZIER", "INTEL", "FLEET", "ARMY", "TREASURY", "COMPNOR", "GUARD", "SPEAKER"}
C.OFFICES = {
    VIZIER = {name = "Grand Vizier", short = "Vizier",
              bonus = "Authority +%d a week.", risk = "Leaks your plans: factions grow faster.",
              lore = {"SATE_PESTAGE"}},
    INTEL = {name = "Director of Imperial Intelligence", short = "Intelligence",
             bonus = "Warns of plots early; covert operations +%d%%.", risk = "Hides plots; helps the independence faction.",
             lore = {"YSANNE_ISARD", "ISARD_LUSANKYA"}},
    FLEET = {name = "Supreme Commander of the Fleet", short = "Fleet",
             bonus = "Fleet savings: +%d credits a week.", risk = "Fleet funds go missing.",
             lore = {"THRAWN_CHIMAERA", "PELLAEON_CHIMAERA_GRAND", "PELLAEON_REAPER", "PELLAEON_MEGADOR",
                     "DAALA_GORGON", "DAALA_KNIGHT_HAMMER"}},
    ARMY = {name = "High Command of the Army", short = "Army",
            bonus = "Stability +%d.", risk = "Garrisons stir unrest: stability falls.", lore = {}},
    TREASURY = {name = "Minister of Industry", short = "Industry",
                bonus = "Income +%d credits a week.", risk = "Embezzles: you lose income.", lore = {"VORRU", "VORRU_TEAM"}},
    COMPNOR = {name = "Director of COMPNOR", short = "COMPNOR",
               bonus = "Loyalty +%d everywhere.", risk = "Propaganda turns sour: loyalty falls.", lore = {}},
    GUARD = {name = "Commander of the Royal Guard", short = "Royal Guard",
             bonus = "Factions grow %d%% slower.", risk = "Factions grow faster.",
             lore = {"CARNOR_JAX", "FLIM_TIERCE_IRONHAND"}},
    SPEAKER = {name = "Speaker of the Moff Council", short = "Moff Council",
               bonus = "Moffs' loyalty +%d.", risk = "Leads the Moffs against you.", lore = {"HISSA_MOFFSHIP"},
               palpatine = {name = "Dark Side Adviser", short = "Dark Side",
                            bonus = "Fear: loyalty +%d.", risk = "Answers only to the Emperor."}},
}
C.OFFICE_CLASSES = {
    INTEL = {"DIRECTOR_INTELLIGENCE"},
    FLEET = {"SUPREME_COMMANDER"},
}
C.OFFICE_RISK = 35
C.OFFICE_INFLUENCE = 4
C.OFFICE_VALUES = {VIZIER = 6, INTEL = 30, FLEET = 600, ARMY = 4, TREASURY = 700, COMPNOR = 8, GUARD = 30, SPEAKER = 8}

C.DISMISS = {PROBATION = 10, EARLY = 1.5}
C.FADE_MAX = 10
C.OLD_ORDER = 20

C.WANTS = {
    PASSED = -12, WEEKS = 10, OTHER_POST = 0.5, MIN_POWER = 3,
    NATURE = {ambitious = 1.6, schemer = 1.3, corrupt = 1.2, paranoid = 1.2, pragmatist = 0.7, loyalist = 0.4},
    OFFICES = {
        SPEAKER = {top_moff = true},
        FLEET = {fleet = "grand_admiral", classes = {"GRAND_ADMIRAL", "GRAND_ADMIRAL_MOFF", "SUPREME_COMMANDER",
                                                     "HIGH_ADMIRAL", "FLEET_ADMIRAL"}},
        ARMY = {classes = {"GENERAL", "HIGH_GENERAL", "GRAND_GENERAL", "SUPERIOR_GENERAL", "MARSHAL", "BARON_GENERAL"}},
        INTEL = {classes = {"DIRECTOR_INTELLIGENCE", "INTELLIGENCE", "INTEL"}},
        VIZIER = {classes = {"ADVISOR", "IMPERIAL_ADVISOR", "CHANCELLOR", "CHIEF_ADMINISTRATOR"}},
        TREASURY = {classes = {"CEO", "CHAIRMAN", "MASTER_IMPERIAL_PROJECTS"}, traits = {"administrator"}, min_power = 5},
        GUARD = {classes = {"ROYAL_GUARD", "EMPERORS_HAND"}},
        COMPNOR = {classes = {"INSPECTOR", "COMMANDANT"}},
    },
}

C.START_ROLES = {
    PESTAGE = {
        {name = "Ysanne Isard", office = "INTEL", heir = "ISARD", release = {"CCOGM", "PALPATINE"}},
        {name = "Carnor Jax", office = "GUARD", heir = "JAX", release = {"PALPATINE"}},
        {name = "Bertroff Hissa", office = "SPEAKER", title = "grand_moff", heir = "CCOGM", release = {"ISARD", "PALPATINE"}},
        {name = "Paltr Carvin", office = "ARMY"},
    },
    ISARD = {
        {name = "Cronal", office = "INTEL"},
    },
    CCOGM = {
        {name = "Bertroff Hissa", office = "SPEAKER", title = "grand_moff", leads = true},
        {name = "Rajah Ubooki", office = "INTEL"},
        {name = "Heingort Giddis", office = "VIZIER"},
    },
    PALPATINE = {
        {name = "Carnor Jax", office = "GUARD", protected = true},
        {name = "Gilad Pellaeon", protected = true, present = true, keep_rank = true},
        {name = "Cronal", office = "INTEL"},
    },
}
C.START_RANKS = {["Uther Kermen"] = {fleet = "grand_admiral"}}

C.TERRITORY = {
    COVET_BASE = 3, COVET_PER_WEEK = 1, COVET_CAP = 15, COVET_RIVAL = 6, COVET_EVENT = 15,
    INFRINGED = -8, INFRINGED_RIVAL = 35, WEEKS = 10,
    LANDS_TAKEN = -15, VASSAL_TAKEN = -10, VASSAL_TAKEN_RIVAL = 40,
    HOARD = 3, HOARD_CAP = 12, HOARD_RIVAL = 2, TRESPASS_RIVAL = 4,
    DENOUNCE = {MIN_RIVALS = 2, PER_RIVAL = 2, WEEKS = 4, COOLDOWN = 20, INVESTIGATE = 8, TREASON_BONUS = 25,
                BACKED = 8, DISMISSED = -8, ACCUSED = -10},
}

C.NOT_COURTIERS = {["TX-5532"] = true, ["Mak Tennar"] = true, ["Tacker"] = true, ["Grath"] = true,
                   ["Bly"] = true, ["Cody"] = true, ["Klick"] = true, ["Razor"] = true, ["Stak"] = true}
C.HEIR_LOYALTY = -30
C.NEXT_LOYALTY = -15
C.HEIR_PULL = 14

C.REGIME_OFFICES = {
    CCOGM = {SPEAKER = {"HISSA_MOFFSHIP", "HISSA_MOFFSHIP_NO_TRANSITION"}, INTEL = {"KADANN_FALSE", "KADANN_FALSE_TEAM"},
             VIZIER = {"JEDGAR_FALSE", "JEDGAR_FALSE_TEAM"}},
}
C.REGIME_DEATHS = {CCOGM = {"SATE_PESTAGE", "PESTAGE_TEAM"}, ISARD = {"SATE_PESTAGE", "PESTAGE_TEAM"}}

C.SUCCESSION_EVENTS = {
    ISARD = {object = "PROJECT_AMBITION_DUMMY", disloyal = 75, succession = 30},
    CCOGM = {object = "DUMMY_REGICIDE_CCOGM", disloyal = 75, succession = 30},
    THRAWN = {object = "DUMMY_REGICIDE_THRAWN", disloyal = 60, succession = 25},
    JAX = {object = "DUMMY_REGICIDE_JAX", disloyal = 60, succession = 25},
    DAALA = {object = "DUMMY_REGICIDE_DAALA", disloyal = 55, succession = 25},
    PELLAEON = {object = "DUMMY_REGICIDE_PELLAEON", disloyal = 50, succession = 20},
}
C.DISLOYAL_FACTIONS = {"autonomy", "independence", "defection", "succession"}
C.LOYALIST_FLIP = {FLIP = 40, FLIP_TRUE = 8, FLIP_OPINION = -30, FLIP_WEEKS = 12}

C.SHOCKS = {
    PALPATINE_KILLED = {text = "Emperor Palpatine killed", value = -15, until_year = 6, before_year = 5},
    SUCCESSION = {text = "Succession crisis", value = -10, months = 6},
}

C.LEGITIMACY_GAINS = {SECTOR_UNITED = 3, VASSAL_WORLD = 2, WORLD_REVOLTS = 2, VASSAL_FACTION = 5, VASSAL_WARLORD = 8}

C.PARTIAL_SECTOR = {PER_SHARE = 16, GROW = 16, CAP = 12}
C.UNDERWORLD = {PER_TIER = 2, CAP = 10}
C.LIEGE_PULL = 15
C.INFLUENCE = {PULL_FROM = 50, FACTION_WEIGHT = 0.05}

C.REGIMES = {
    PESTAGE = {leader = "Sate Pestage", title = "Grand Vizier", rank = "Grand Vizier", name = "Sate Pestage", figure = "SATE_PESTAGE", stability = 45, loyalty = -15,
               revoke = "cost", crisis = 1.6, breakaway = 1.5, defect = 1.5, covert = 0, integration = 0.8,
               authority = 3, office_cost = 0.5,
               perks = "Patronage is cheap: honours and offices cost half.",
               flaws = "The Crisis at full strength; Moffs ignore orders."},
    ISARD = {leader = "Ysanne Isard", title = "Imperial Director", rank = "Imperial Director", name = "Ysanne Isard", figure = "YSANNE_ISARD",
             stability = 42, loyalty = -6, revoke = "free", crisis = 1.1, breakaway = 1.2, defect = 1.6, covert = 25,
             integration = 1.0, authority = 4, plots = 0.5, grand_moffs = -15,
             perks = "Covert operations +25%; plots are found early.",
             flaws = "Purges: Grand Moffs hate her; defections are likely."},
    CCOGM = {leader = "Grand Moff Bertroff Hissa", title = "Central Committee of Grand Moffs", rank = "Head of the Committee",
             name = "Bertroff Hissa", figure = "TRIOCULUS", emperor = "Emperor Trioculus", leader_figure = "HISSA_MOFFSHIP",
             stability = 45, loyalty = 0,
             revoke = "reason", crisis = 1.0, breakaway = 0.7, defect = 1.0, covert = 0, integration = 1.0,
             authority = 3, grand_moffs = 20, moffs = -8, income = -0.15,
             perks = "Grand Moffs are loyal; few great breakaways.",
             flaws = "A weak centre: Moffs grow restless; core income -15%."},
    THRAWN = {leader = "High Grand Admiral Thrawn", title = "High Grand Admiral", rank = "High Grand Admiral", name = "Thrawn", figure = "THRAWN_CHIMAERA", stability = 62,
              loyalty = 6, revoke = "free", crisis = 0.6, breakaway = 0.8, defect = 0.8, covert = 10,
              integration = 1.2, authority = 5, merit = true, legitimacy = 1,
              perks = "Skill counts at court; +1 legitimacy per world taken.",
              flaws = "Xenophobes resent an alien; collapse risk when he falls."},
    INTERREGNUM = {leader = "the Moff Council", title = "Interregnum", rank = "Interregnum", name = "Moff Council", stability = 28, loyalty = -12, revoke = "reason",
                   crisis = 1.4, breakaway = 1.8, defect = 1.4, covert = 0, integration = 0.8, authority = 2,
                   perks = "None.", flaws = "Factions spike; breakaways are likely."},
    PALPATINE = {leader = "Emperor Palpatine", title = "Emperor reborn", rank = "Emperor", name = "Palpatine", figure = "EMPEROR_PALPATINE", stability = 70,
                 loyalty = 0, revoke = "free", crisis = 0.3, breakaway = 0.2, defect = 0.1, covert = 15,
                 integration = 1.6, authority = 6, fear = 65, drained = 0.5, coalition = -30, tithe = 0.008,
                 perks = "Fear: lords rarely petition or plot; integrations come fast.",
                 flaws = "The galaxy unites against you; it all falls apart if he dies."},
    JAX = {leader = "Carnor Jax", title = "Head of the Ruling Council", rank = "Head of the Council", name = "Carnor Jax", figure = "CARNOR_JAX", stability = 38,
           loyalty = -6, revoke = "cost", crisis = 1.1, breakaway = 1.2, defect = 1.2, covert = 10, integration = 0.9,
           authority = 3, offices = 1.25, guard = 25,
           perks = "Court offices work 25% better; the Royal Guard is his.",
           flaws = "A usurper's legitimacy; Royal Guard dissent."},
    DAALA = {leader = "Admiral Natasi Daala", title = "Supreme Commander", rank = "Supreme Commander", name = "Natasi Daala", figure = "DAALA_GORGON", stability = 48,
             loyalty = -4, revoke = "free", crisis = 0.9, breakaway = 1.0, defect = 1.0, covert = 0, integration = 1.8,
             authority = 4, moffs = -10,
             perks = "Warlord summit: integrating minor warlords is much easier.",
             flaws = "The Moffs distrust her; a Moff coup is possible."},
    PELLAEON = {leader = "Grand Admiral Gilad Pellaeon", title = "Supreme Commander", rank = "Supreme Commander", name = "Gilad Pellaeon", figure = "PELLAEON_CHIMAERA_GRAND",
                stability = 64, loyalty = 4, revoke = "cost", crisis = 0.5, breakaway = 0.7, defect = 0.7, covert = 0,
                integration = 1.2, authority = 4, loyalty_rise = 1,
                perks = "Stability; loyalty slowly rises; peace is easier to make.",
                flaws = "Slow expansion; Moff Council intrigue."},
    LAMBDA = {leader = "Moff Quarsh Panaka", title = "Moff of the Lambda Sector", rank = "Moff", name = "Quarsh Panaka", figure = "PANAKA_THEED", stability = 48,
              loyalty = 2, revoke = "cost", crisis = 0.9, breakaway = 1.1, defect = 1.0, covert = 10, integration = 1.0,
              authority = 4, regional = true,
              perks = "A regional command: a small court, and Intelligence works well (+10%).",
              flaws = "No help from the core: every world lost weighs heavily."},
    EMPIRE = {leader = "the Imperial Ruling Council", title = "Imperial Ruling Council", rank = "Imperial", name = "Ruling Council", stability = 50, loyalty = 0,
              revoke = "cost", crisis = 0.8, breakaway = 1.0, defect = 1.0, covert = 0, integration = 1.0, authority = 4,
              perks = "None.", flaws = "None."},
}
C.SUCCESSION = {"PESTAGE", "ISARD", "THRAWN", "JAX", "DAALA", "PELLAEON"}
C.SUCCESSION_RETURN = "PALPATINE"
C.REGIME_INDEX = {[1] = "PESTAGE", [2] = "ISARD", [3] = "THRAWN", [4] = "PALPATINE", [5] = "JAX", [6] = "DAALA",
                  [7] = "PELLAEON"}

C.STABILITY = {
    DRIFT = 0.15,
    LOYALTY = 0.5,
    LOYALTY_CAP = 12,
    LEGITIMACY = 0.3,
    WORLD_LOST = 3, WORLD_GAINED = 1, LOSS_CAP = 15,
    TAX_PER_WORLD = 15,
    WORDS = {{20, "Collapsing"}, {40, "Unsteady"}, {60, "Holding"}, {80, "Steady"}, {101, "Iron-fisted"}},
}
C.CRISIS = {
    CHANCE = 0.9,
    COOLDOWN = 3,
    AWOL_WEEKS = 4,
    AWOL_BRIBE = 2500,
    PROCLAIM_BELOW = 25,
}

C.REGIME_EVENTS = {
    ISARD = {chance = 12, kind = "purge"},
    CCOGM = {chance = 10, kind = "infighting"},
    THRAWN = {chance = 6, kind = "old_guard"},
    JAX = {chance = 10, kind = "guard_dissent"},
    DAALA = {chance = 8, kind = "coup"},
    PELLAEON = {chance = 8, kind = "council_intrigue"},
    INTERREGNUM = {chance = 12, kind = "infighting"},
}
C.FALL_SHOCK = {PALPATINE = {stability = 35, opinion = -30}, THRAWN = {stability = 15, opinion = -10}}
C.ABSORBED_SECTOR = 3

C.FACTION_ORDER = {"loyalists", "autonomy", "succession", "defection", "independence"}
C.FACTION_MARK = {loyalists = "green", autonomy = "yellow", succession = "yellow", defection = "red", independence = "red"}
C.LOYALISTS = {JOIN = 65, LEAVE = 48}
C.INTEREST = 25
C.FACTION_TIES = {FRIEND = 12, RIVAL = 10}
C.FACTIONS = {
    loyalists = {name = "Loyalists", goal = "Support the throne.", ultimatum = nil},
    autonomy = {name = "Autonomy", goal = "Lower taxes, no minders, more troops.", threshold = 30,
                ultimatum = "Grant the Moffs autonomy: lower taxes and recall the minders."},
    independence = {name = "Independence", goal = "Rule their sectors as independent warlords.", threshold = 25,
                    ultimatum = "Recognise their sectors as independent."},
    defection = {name = "Defection", goal = "Join a rival power (no ultimatum).", threshold = nil},
    succession = {name = "Succession", goal = "Back another heir to the throne.", threshold = nil},
}
C.FACTION_PROGRESS = 0.3
C.FACTION_DECAY = 4
C.BREAKAWAY_AI = "WarlordAI"
C.ULTIMATUM_WEEKS = 2
C.DEFECT_CHANCE = 0.3
C.DEFECT_BELOW = 30
C.DEFECT_WARNING = 2
C.BREAKAWAY_LOYALTY = 25
C.FOLLOW_LOYALTY = 35
C.BREAKAWAY_STABILITY = 5

C.AI = {LOYALTY = 15, STABILITY = 12, HONOUR_BELOW = 42, BRIBE_BELOW = 30, BRIBE_CREDITS_ABOVE = 15000, GRANT_BELOW = 60}

C.PETITION_CHANCE = 6
C.PETITION_WEEKS = 3
C.PETITION_MAX = 4
C.PETITION_COST = 6
C.PETITIONS = {
    title = "asks to be granted %s.",
    office = "asks for the office of %s.",
    troops = "asks for %d credits to defend their sector.",
    taxes = "asks leave to raise taxes in their sector.",
    rival = "demands that their rival %s be dismissed.",
    dispute = "and %s quarrel over %s, and ask the throne to settle it.",
}
C.TROOPS_CREDITS = 1500
C.PETITION_WEIGHTS = {dispute = 1.2, title = 1.5, office = 1, troops = 1, taxes = 0.7, rival = 0.8}
C.PETITION_COUNT = {75, 20, 5}
C.DISPUTE = {WON = 10, LOST = -8, IGNORED = -3, RIVALS = 30, WEEKS = 12}
C.DISPUTES = {
    "the rights to a bacta shipment", "precedence at the Empire Day review", "a disputed hyperlane toll",
    "the command of a shared garrison", "the salvage of a wrecked freighter", "a stolen protocol droid",
    "the berth of a Star Destroyer at a shared yard", "an insult at a state banquet", "a cancelled marriage contract",
    "the ownership of a moon's mining claims", "who pays for the local stormtrooper barracks", "a gambling debt from Coruscant",
    "the recruitment of the same TIE pilots", "a border survey a decade out of date", "a confiscated art collection",
    "the seating of their envoys at court", "a smuggler both claim to have caught", "the upkeep of a shared listening post",
}

C.HONOUR_WEEKS = 15
C.ACTIONS = {HONOUR = 10, APPOINT = 8, DISMISS = 5, REVOKE = 15, MINDER = 5, ARREST = 25, TRIBUTE_PER_POWER = 150,
             BRIBE_CREDITS = 1500, FEALTY = 20}

C.INTEGRATION = {
    FEALTY_AT = 75,
    BAR_BASE = 8, BAR_PER_WORLD = 2,
    WEEK_BASE = 0.6,
    BORDER = 1.5,
    RIVAL_RATE = 0.6,
}
C.RIVALS = {"PENTASTAR", "GREATER_MALDROOD", "ZSINJ_EMPIRE", "ERIADU_AUTHORITY", "IMPERIAL_PROTEUS"}
C.DEFECT_TO = {"PENTASTAR", "GREATER_MALDROOD", "ZSINJ_EMPIRE", "ERIADU_AUTHORITY", "IMPERIAL_PROTEUS", "REBEL"}

C.OP_ORDER = {"GATHER", "SWAY", "BRIBE", "SABOTAGE", "PROPAGANDA", "STAGE_ATTACK", "ASSASSINATE", "DEFECTION", "INCITE",
              "INCITE_WAR"}
C.INTERNAL_ORDER = {"MINDER", "TREASON", "ARREST", "MURDER"}
C.OPS = {
    GATHER = {name = "Gather intelligence", short = "Gather intel", tier = 1, at = "capital", cost = 500, weeks = 1,
              chance = 85, caught = 0, kill = 0, attitude = 0, xp = 6,
              desc = "Builds the spy network: +25 intel progress (at 100 it rises a tier), and a report on their worlds and leaders. "
                  .. "It can fail, but the operative is never caught."},
    SWAY = {name = "Sway", tier = 1, at = "capital", cost = 1200, weeks = 2, chance = 70, caught = 0, kill = 0, attitude = 0,
            influence = 15, xp = 8,
            desc = "Wins friends at their court: your influence over a minor warlord grows; others warm to the Empire. It can "
                .. "fail, but the operative is never caught."},
    BRIBE = {name = "Bribe", tier = 2, at = "planet", pick = {"planet"}, cost = 2500, weeks = 1, chance = 60, caught = 20,
             kill = 30, attitude = -12, lasts = 5, xp = 12,
             desc = "Half the garrison buildings on a world stay idle: no troops from them in land battles for 5 weeks."},
    SABOTAGE = {name = "Sabotage", tier = 2, at = "planet", pick = {"planet", "building"}, cost = 1800, weeks = 1, chance = 55,
                caught = 25, kill = 40, attitude = -12, xp = 12,
                desc = "Destroys a building of your choice."},
    PROPAGANDA = {name = "Disseminate propaganda", short = "Propaganda", tier = 3, at = "planet", pick = {"planet"}, cost = 2000,
                  weeks = 2, chance = 60, caught = 15, kill = 25, attitude = -10, lasts = 10, capital = -25, xp = 15,
                  desc = "For 10 weeks the world would rise for the Empire rather than anyone else (until it changes hands)."},
    STAGE_ATTACK = {name = "Stage an attack", short = "Staged attack", tier = 3, at = "planet", pick = {"planet", "faction"},
                    cost = 3000, weeks = 2, chance = 50, caught = 30, kill = 40, attitude = -20, influence = -3, lasts = 10,
                    opinion = -30, xp = 18,
                    desc = "An atrocity blamed on another power: the world's loyalty falls, and its owner turns on the power blamed."},
    ASSASSINATE = {name = "Assassinate", tier = 4, at = "hero", pick = {"hero"}, cost = 5000, weeks = 2, chance = 35, caught = 40,
                   kill = 60, attitude = -35, xp = 25,
                   desc = "Kills one of their heroes."},
    DEFECTION = {name = "Encourage defection", short = "Defection", tier = 4, at = "hero", pick = {"hero"}, cost = 4000, weeks = 3,
                 chance = 40, caught = 30, kill = 40, attitude = -25, major = -15, republic = -30, xp = 25,
                 desc = "One of their heroes joins the Empire and is brought to your capital. Hard against great powers, "
                     .. "very hard against the New Republic."},
    INCITE = {name = "Incite revolt", tier = 5, at = "planet", pick = {"planet"}, cost = 4000, weeks = 2, chance = 25,
              per_influence = 6, caught = 30, kill = 50, attitude = -30, xp = 30,
              desc = "The world rises at once for the power it prefers. Easier the less loyal it is."},
    INCITE_WAR = {name = "Incite war", tier = 5, at = "capital", pick = {"faction"}, cost = 6000, weeks = 3, chance = 35,
                  caught = 35, kill = 60, attitude = -40, opinion = -40, xp = 35, caught_fails = true,
                  desc = "Forged proof turns another power on them: every treaty between the two ends and they go to war."},
    MINDER = {name = "Minder", internal = true, at = "char", pick = {"char"}, cost = 0, authority = 5, weeks = 1, chance = 100,
              caught = 0, kill = 0, xp = 2, open = true, protected_ok = true,
              desc = "An operative watches them: out of every faction while it lasts (a faction's leader cannot issue "
                  .. "ultimatums or secede). They resent it. Stays until recalled."},
    TREASON = {name = "Accuse of treason", short = "Treason", internal = true, at = "char", pick = {"char"}, cost = 1500,
               authority = 10, weeks = 2, chance = 45, caught = 20, kill = 20, xp = 15,
               desc = "Proof of treason: they are branded a traitor, and every title can be taken from them without "
                   .. "angering the court. Easier the less loyal they are."},
    ARREST = {name = "Attempt to arrest", short = "Arrest", internal = true, at = "char", pick = {"char"}, cost = 2000,
              authority = 15, weeks = 1, chance = 55, traitor = 25, caught = 25, kill = 30, xp = 20,
              desc = "Strips every title and post at once and sends them to the Imperial Prison. Rivals cheer, friends "
                  .. "rage; without the traitor's brand it looks tyrannical."},
    MURDER = {name = "Assassinate", internal = true, at = "char", pick = {"char"}, cost = 4000, authority = 10, weeks = 2,
              chance = 45, caught = 30, kill = 50, xp = 25,
              desc = "Their death looks like an accident; their titles fall vacant. Caught, the throne looks murderous."},
    COUNTER = {name = "Counter-intelligence", short = "Counter-intel", cost = 1000, weeks = 1, chance = 100, caught = 0, attitude = 0,
               lasts = 8, desc = "For 8 weeks: plots found sooner, factions slowed, enemy operations hampered."},
}
C.COVERT = {RANK = 5, DIRECTOR = 20, CAPITAL = -15, CAUGHT_TIER = 0.25, DIRECTOR_LOYALTY = 50,
            ARREST_TYRANNY = -8, ARREST_STABILITY = 3, ARREST_RIVALS = 10, ARREST_FRIENDS = -20, PRISON_LOYALTY = -60,
            MURDER_CAUGHT = -15, MURDER_STABILITY = 8, TREASON_CAUGHT = -25, LOYALTY_EASE = 0.5}

C.SPY = {MAX = 5, PROGRESS = 100, GATHER = 25,
         NAMES = {[0] = "No network", "Contacts", "Informants", "Agents in place", "Deep cover", "Infiltrated"},
         PROBES = {"VIPER_PROBE_DROID_COMPANY", "VIPER_PROBE_DROID"},
         PEACE = {CEASEFIRE = true, ALLIANCE = true, VASSAL = true}}

C.AGENTS = {RECRUIT_WEEKS = 5, RECRUIT_AUTHORITY = 10, RECRUIT_CREDITS = 1500, MAX = 5,
            XP = {20, 50, 90, 140},
            TYPES = {"COURT_OPERATIVE_1", "COURT_OPERATIVE_2", "COURT_OPERATIVE_3", "COURT_OPERATIVE_4", "COURT_OPERATIVE_5",
                     "COURT_OPERATIVE_6"},
            NEVER = {["Ysanne Isard"] = true},
            LORE = {"Rukh", "Blaise", "Montra Varn", "Cha Raas", "Malau Jocaos", "Anlys Takkar", "Cass Maston", "Rodin Baem",
                    "Victor Grieves", "Zam Basdor", "Drend Navett", "Erron Irbian", "Mahd Windcaller", "Kadann", "Lumiya",
                    "Brakiss", "Heingort Giddis", "Rajah Ubooki"},
            RANKS = {"Junior Agent", "Agent", "Senior Agent", "Special Agent", "Shadow Agent"},
            NUMERALS = {"I", "II", "III", "IV", "V"}}

C.AGENT_TRAIT_CHANCE = 35
C.AGENT_TRAIT_EFFECT = {OP_SUCCESS = 15, OP_CAUGHT = -10, DISGUISE_CAUGHT = -10, COURT_SUCCESS = 15, CONNECTED_COST = 0.75}
C.AGENT_TRAIT_ORDER = {"RECON", "SILVER_TONGUE", "PAYMASTER", "SABOTEUR", "PROPAGANDIST", "TERRORIST", "ASSASSIN",
                       "RECRUITER", "AGITATOR", "PROVOCATEUR", "DISGUISE", "CONNECTED", "FEARED", "HYPERDRIVE"}
C.AGENT_TRAITS = {
    RECON = {name = "Recon Expert", op = "GATHER",
             desc = "Reads a power's secrets like an open file: Gather intelligence +15% success."},
    SILVER_TONGUE = {name = "Silver Tongue", op = "SWAY",
                     desc = "Ministers listen when they speak: Sway +15% success."},
    PAYMASTER = {name = "Paymaster", op = "BRIBE",
                 desc = "Knows every officer's price: Bribe +15% success, -10% to be caught."},
    SABOTEUR = {name = "Saboteur", op = "SABOTAGE",
                desc = "A charge in the right place: Sabotage +15% success, -10% to be caught."},
    PROPAGANDIST = {name = "Propagandist", op = "PROPAGANDA",
                    desc = "Turns a world's mood with a broadcast: Disseminate propaganda +15% success, -10% to be caught."},
    TERRORIST = {name = "Terrorist", op = "STAGE_ATTACK",
                 desc = "Leaves another power's fingerprints on every atrocity: Stage an attack +15% success, "
                     .. "-10% to be caught."},
    ASSASSIN = {name = "Assassin", op = "ASSASSINATE",
                desc = "Never misses: Assassinate +15% success, -10% to be caught."},
    RECRUITER = {name = "Recruiter", op = "DEFECTION",
                 desc = "Finds the doubt in every loyal heart: Encourage defection +15% success, -10% to be caught."},
    AGITATOR = {name = "Agitator", op = "INCITE",
                desc = "Riots follow in their wake: Incite revolt +15% success, -10% to be caught."},
    PROVOCATEUR = {name = "Provocateur", op = "INCITE_WAR",
                   desc = "Forgeries no court can doubt: Incite war +15% success, -10% to be caught."},
    DISGUISE = {name = "Master of Disguise",
                desc = "A hundred faces, none their own: -10% to be caught in every operation."},
    CONNECTED = {name = "Well Connected",
                 desc = "Friends in every port and office: their operations cost 25% fewer credits."},
    FEARED = {name = "Feared at Court",
              desc = "Lords lower their voices when they pass: +15% success in operations against the court."},
    HYPERDRIVE = {name = "Experimental Starship Hyperdrive", fast = true,
                  desc = "Flies a classified personal agent vessel: twice as fast between worlds."},
}
C.ATTITUDE_FADE = 1

C.INTEL_TEXT = {
    GATHER_ok = {"Ubiqtorate analysts sift {agent}'s report from {world}: {target} has fewer secrets now.",
                 "{agent}'s dead drop on {world} yields fresh files on {target}."},
    GATHER_fail = {"{agent} returns from {world} empty-handed: {target}'s counter-intelligence was alert.",
                   "No word from {world}. {agent} found nothing on {target} this time."},
    SWAY_ok = {"Credits and quiet promises on {world}: friends of the Empire rise in {target}'s court.",
               "{target}'s ministers begin to listen when the Empire speaks."},
    SWAY_fail = {"{target}'s officials pocket the gifts and promise nothing.",
                 "{agent}'s overtures on {world} are politely ignored."},
    BRIBE_ok = {"The garrison commanders of {world} have been paid. Their troops will stay in barracks.",
                "Credits change hands on {world}: half its garrison will not answer the call to arms."},
    BRIBE_fail = {"The officers on {world} refuse the Empire's credits.",
                  "{agent}'s bribe is turned down on {world}. The garrison stays loyal to {target}."},
    SABOTAGE_ok = {"A charge in the right place: {target}'s {building} on {world} is rubble.",
                   "Fire on {world}. {target}'s {building} will not be rebuilt soon."},
    SABOTAGE_fail = {"{agent}'s charges never go off. The {building} on {world} still stands.",
                     "Security on {world} is too tight: the sabotage is called off."},
    PROPAGANDA_ok = {"Imperial broadcasts flood the HoloNet on {world}: its people begin to look to the Empire.",
                     "Posters of the Emperor's peace appear across {world}. The people are listening."},
    PROPAGANDA_fail = {"The people of {world} jeer at the Imperial broadcasts.",
                       "{target} jams the Imperial broadcasts over {world}."},
    PROPAGANDA_end = {"The Imperial broadcasts on {world} fall silent."},
    STAGE_ATTACK_ok = {"Smoke over {world}. Every trace points to {other}; {target} swears vengeance.",
                       "An atrocity on {world}, and {other}'s insignia on the wreckage. {target} will not forget."},
    STAGE_ATTACK_fail = {"The staged attack on {world} falls apart before it begins.",
                         "Too many loose ends on {world}: the false flag is abandoned."},
    ASSASSINATE_ok = {"{hero} is dead. Imperial Intelligence denies all knowledge.",
                      "A single shot on {world}: {hero} will trouble the Empire no more."},
    ASSASSINATE_fail = {"{hero} survives: {agent}'s shot goes wide on {world}.",
                        "{hero}'s guards were too many. The assassination fails."},
    DEFECTION_ok = {"{hero} turns their back on {target} and reports to {capital}. Welcome to the Empire.",
                    "{hero} accepts the Empire's terms and slips away to {capital}."},
    DEFECTION_fail = {"{hero} refuses the Empire's offer and stays loyal to {target}.",
                      "{hero} listens, then sends {agent} away. No defection."},
    INCITE_ok = {"Riots become revolution: {world} rises against {target}!",
                 "The streets of {world} burn. The planet throws off {target}'s rule!"},
    INCITE_fail = {"{world} grumbles, but does not rise. {target}'s grip holds.",
                   "The uprising on {world} is crushed before it starts."},
    INCITE_WAR_ok = {"Forged proof reaches {other}: they accuse {target} of treachery and declare war!",
                     "{other} believes every word. War with {target} is declared."},
    INCITE_WAR_fail = {"{other} doubts the evidence. There will be no war with {target}.",
                       "The forgeries are exposed. {other} and {target} keep the peace."},
    TREASON_ok = {"Evidence surfaces: {char} is branded a traitor to the Empire.",
                  "The files are damning. {char} stands accused of treason."},
    TREASON_fail = {"The case against {char} collapses for lack of proof."},
    ARREST_ok = {"Stormtroopers seize {char}. The doors of the Imperial Prison close behind them.",
                 "{char} is taken in the night. The Imperial Prison has a new guest."},
    ARREST_fail = {"{char} slips the net before the arrest."},
    MURDER_ok = {"{char} is dead. A tragic accident, the court is told.",
                 "{char}'s speeder never arrives. The court mourns, and wonders."},
    MURDER_fail = {"{char} survives the 'accident' unharmed."},
    MINDER_ok = {"{agent} now shadows {char}'s every move."},
    MINDER_end = {"{agent} is recalled from watching {char}."},
    caught = {"{agent} is unmasked by {target}. Expect their anger.",
              "{target} catches {agent} red-handed. The Empire's hand is exposed."},
    caught_court = {"{char} learns who was behind it. Intelligence has made an enemy.",
                    "The plot against {char} is uncovered. The court whispers."},
    killed = {"{agent} is executed by {target}. Imperial Intelligence mourns quietly.",
              "{agent} will not come home: {target} has executed them."},
    killed_court = {"{agent} vanishes. They will not be found."},
    promoted = {"{agent} is promoted to {rank}. The Director takes note."},
    trait = {"{agent} has proven themselves: {trait}.", "The Director's file on {agent} gains a line: {trait}."},
    lost = {"Contact with {agent} is lost."},
    recruit = {"{agent} takes the oath of Imperial Intelligence on {world}."},
    tier_up = {"Our network in {target} grows: tier {tier}, {tiername}.",
               "New agents in place inside {target}: network tier {tier}, {tiername}."},
    probe = {"A probe droid reports from {world}: our first agents are inside {target}."},
    tier_down = {"The failure costs us agents in {target}: network down to tier {tier}.",
                 "{target} rolls up part of our network: tier {tier} now."},
    abandon = {"{agent} left their post. The {op} is called off."},
}

C.FIRST_NAMES = {"Adar", "Aldo", "Aren", "Bastra", "Belis", "Brusk", "Caed", "Cassik", "Corvin", "Dalvo", "Davor",
                 "Edrin", "Elsa", "Feyor", "Garm", "Gavrin", "Hadra", "Helsin", "Ivo", "Jorrin", "Kalen", "Kaius",
                 "Lenna", "Loran", "Marec", "Mirel", "Nadine", "Noll", "Orlan", "Osk", "Pell", "Quin", "Rasa",
                 "Rennik", "Sabra", "Sel", "Tavik", "Teodor", "Ulla", "Varn", "Vessa", "Wyl", "Yorel", "Zandra",
                 "Arvel", "Brin", "Dace", "Essar", "Jandt", "Kesh", "Mott", "Nyle", "Riss", "Sorn", "Tyv", "Vell"}
C.SURNAMES = {"Ablard", "Arkos", "Bellac", "Brandis", "Carvane", "Corlis", "Dannet", "Derrow", "Drayen", "Ellis",
              "Fenn", "Gorvane", "Hallor", "Harkos", "Ivarre", "Jandrell", "Kastor", "Kellan", "Lorrim",
              "Malvek", "Marrak", "Nerovar", "Orvane", "Pallis", "Quarrel", "Ravell", "Renn", "Sarkovin",
              "Selden", "Strallow", "Tarvos", "Thessar", "Ulmont", "Varrick", "Veddar", "Wex", "Yarlan", "Zaltane",
              "Crane", "Dovarn", "Esterhal", "Grath", "Kerrig", "Lothren", "Mordane", "Thorne", "Vance", "Wren",
              "Brakk", "Dren", "Hask", "Kaine", "Lorne", "Mekk", "Nevik", "Orrus", "Praxx", "Rodd", "Sarn", "Trell",
              "Vosk", "Zell", "Cardaan", "Delvor", "Faal", "Gennet", "Jerrik", "Kolaar", "Mallor", "Pradd"}

return C
