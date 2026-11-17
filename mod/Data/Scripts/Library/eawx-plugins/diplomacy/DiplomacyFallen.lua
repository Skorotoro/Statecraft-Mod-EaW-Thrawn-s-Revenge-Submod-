local FACTIONS = require("eawx-plugins/diplomacy/DiplomacyFactions")

local Fallen = {}

local GOLD = {r = 255, g = 220, b = 120}

local TEXT = {
    REBEL = "{name} is no more. Its last world has fallen and its leaders are dead or scattered. The hope that "
        .. "was kindled at Yavin and Endor gutters out, and the galaxy wonders whether it will ever burn again.",
    EMPIRE = "The last world of {name} has fallen. The New Order that once ruled a million systems from Coruscant "
        .. "is a memory now, and a warning to every would-be emperor who comes after it.",
    HUTT_CARTELS = "The Hutt kajidics have lost their last world. Their palaces are looted, their debts go "
        .. "uncollected, and the spice lanes answer to new masters. The underworld will remember the Hutts, but it "
        .. "will no longer fear them.",
    ERIADU_AUTHORITY = "The Eriadu Authority is broken. Tarkin's home world has fallen, and with it the dream of a "
        .. "Seswenna that would rule the Outer Rim as the Grand Moff once did.",
    GREATER_MALDROOD = "Greater Maldrood is no more. Teradoc's crimson-hulled fleets are scattered, and his red "
        .. "banners come down across the sector.",
    PENTASTAR = "The Pentastar Alignment has collapsed. Ardus Kaine's corporate empire, built to bring order back "
        .. "to the galaxy's markets, has lost its last world; its shareholders flee with whatever they can carry.",
    ZSINJ_EMPIRE = "Zsinj's empire has fallen. The warlord of the Quelii sector, who loved a grand gesture above "
        .. "all things, has lost his last world. The Iron Fist has no harbour left.",
    CORPORATE_SECTOR = "The Corporate Sector Authority has lost its last holding. Its Espos lay down their arms, the "
        .. "Direx Board scatters, and the profits of a thousand worlds go uncounted.",
    HAPES_CONSORTIUM = "The Hapes Consortium is overthrown. The Fountain Palace has fallen, and the Hapan Cluster, "
        .. "closed to outsiders for three thousand years, lies open at last.",
    EMPIREOFTHEHAND = "The Empire of the Hand has lost its last world. Thrawn's distant domain beyond the edge of "
        .. "the known galaxy goes dark, and the spires of Nirauan stand empty.",
    IMPERIAL_PROTEUS = "{name} has fallen. One more warlord's throne lies broken, and the Empire's heirs "
        .. "grow fewer.",
    YEVETHA = "The Duskhan League is destroyed. N'Zoth's dream of a pure Koornacht Cluster, paid for in the blood "
        .. "of every other people there, has ended in fire.",
    UNDERWORLD = "{name} has lost its last world. Its lieutenants vanish into the galaxy's back alleys, and rival "
        .. "syndicates carve up what is left.",
    CORELLIA = "Corellia has fallen. The proud Corellian worlds, who always went their own way, have lost the last "
        .. "of their independence.",
    CHISS = "The Chiss Ascendancy has lost its last world in this part of the galaxy. The Ruling Families withdraw "
        .. "behind Csilla's ice and the Unknown Regions' shadows.",
    KILLIK_HIVES = "The Killik Hives are silent. Their nests are broken, and the Joiners who heard their song "
        .. "slowly wake from it.",
    SSIRUUVI_IMPERIUM = "The Ssi-ruuvi Imperium is broken. Its entechment ships are gone, and the worlds it meant to "
        .. "drain of life breathe freely again.",
    MANDALORIANS = "The Mandalorian clans have lost their last world. The armour is packed away and the helmets "
        .. "laid down, but Mandalorians have come back from worse.",
    WARLORD_LAMBDA = "The Lambda Sector's last world has fallen. Par Lankin's court at Rintonne is gone, and the "
        .. "sector no longer kneels to a man who crowned himself.",
    WARLORD_ZERO_COMMAND = "Zero Command is no more. Blitzer Harrsk's Deep Core fortress worlds have fallen one by "
        .. "one, and the Whirlwind has no harbour left.",
    WARLORD_ELROOD = "The Elrood Sector is free of its warlord. Villis Andal's little realm ends where it began.",
    WARLORD_ANTEMERIDIAS = "The Antemeridian Sector is free of its warlord. Tol Getelles' harsh and short rule is "
        .. "over.",
    WARLORD_WILD_SPACE = "Delurin's Empire has fallen. The Dragon of Wild Space has lost his last world.",
    WARLORD_PRENTIOCH = "Prentioch's Dominion has collapsed. Utoxx Prentioch's worlds are taken, and his dominion "
        .. "with them.",
    WARLORD_SECTOR_5 = "Sector 5 is broken. Malfkla Yzu's Constitution sails for a harbour that no longer exists.",
    WARLORD_PRAKITH = "The Protectorate of Prakith has fallen. Foga Brill's reign of terror ends, and nobody on "
        .. "Prakith will mourn the Inquisitor who ruled it.",
    WARLORD_JARDEEN = "Warlord Jardeen is finished. Iolan Gendarr's realm has lost its last world, and the Reliance "
        .. "has nowhere left to run.",
    WARLORD_CIUTRIC_HEGEMONY = "The Ciutric Hegemony is no more. Prince-Admiral Krennel's ambition has failed him "
        .. "at last.",
    WARLORD_KAMINO = "The Dark Apprentice's hold on Kamino is broken. The cloning halls fall silent, and whatever "
        .. "grew in their vats will grow no more.",
    WARLORD_NABOO = "Warlord Naboo has fallen. Quarsh Panaka's rule over the Queen's world ends; Naboo may choose its "
        .. "own rulers again.",
    WARLORD_RADAMA = "The warlord of Ord Radama has lost his last world. Ellor Orgraal's fleet is scattered.",
    WARLORD_TAPANI = "The Tapani Sector's warlord has fallen. Bal Jaset's realm dissolves back into the sector's "
        .. "quarrelling noble houses.",
    WARLORD_GAROS = "Warlord Garos is no more. Zakar's realm, never as large as his ambitions, has lost its last "
        .. "world.",
    WARLORD_MAELSTROM = "Maelstrom Command has collapsed. Torpin's fleets scatter into the storm that gave his "
        .. "realm its name.",
    WARLORD_SHADOWSPAWN = "The Shadow Realm is ended. Cronal, who ruled from the Rim's shadows as Shadowspawn, has "
        .. "lost his last world.",
    WARLORD_PROPHETS = "The Prophets of the Dark Side are scattered. Kadann's visions did not foresee this: the "
        .. "Sith worlds they held are lost to them.",
    WARLORD_TAGGE = "The House of Tagge has fallen. Ulric Tagge's realm has lost its last world, and the Tagge "
        .. "fortune goes down with it.",
    WARLORD_TIERFON = "The Tierfon Sector's warlord has fallen. Supreme Commander Tzenkens has no command left.",
    WARLORD_BAKURA = "Bakura is free of its warlord. Governor Nereus has lost his last world, and the Bakurans may "
        .. "look to their own future at last.",
    WARLORD_BRAK = "The Brak Sector is free. Lesan Ramier's rule has fallen with his last world.",
    WARLORD_TAMARIN = "The Tamarin Sector's warlord is no more. Lobax Resuun's Retribution has no worlds left to "
        .. "avenge.",
    WARLORD_ISECTOR = "The I-sector has fallen. Bliss Shargael's rule ends with his last world.",
    WARLORD_IMPERIAL_LIANNA = "Warlord Lianna is no more. Phillip Santhe's hold on Lianna is broken, and its "
        .. "shipyards build for whoever comes next.",
    WARLORD_QUINTAD = "The Quintad is broken. Thalassa Tarkin's bid to rule in her family's name has failed, and "
        .. "the Tarkin legacy dims once more.",
    WARLORD_DASTA = "The D'Astan Sector has lost its warlord. Ragez D'Asta has nowhere left to raid from.",
    WARLORD_HAMMERS = "The Imperial Hammers are broken. Zel Johans' fleet will strike no more.",
    WARLORD_KASHYYYK = "The warlord of Kashyyyk has fallen. Hindane Darcc's hold on the Wookiee home world is "
        .. "broken, and its forests are free.",
    WARLORD_LUMIYA = "Lumiya's Sith have lost their last world. The Dark Lady slips back into the shadows she came "
        .. "from, as she has done before.",
    WARLORD_ARDA = "Warlord Arda has fallen. Vorrel's walkers stand silent, and Arda is free.",
    WARLORD_SELLASAS = "Warlord Sellasas is no more. Jedselk's rule over Dolla and Sellasas has ended.",
    WARLORD_PROTECTORATE = "The Protectorate has fallen. Adalric Brandl's ambitions end with his last world.",
    WARLORD_ZAARIN_REMNANTS = "The Zaarin Remnants are scattered. Raveen's last stand for Grand Admiral Zaarin's "
        .. "dream has failed.",
    WARLORD_RAYTER = "The Rayter Sector's warlord has fallen. Nile Owen's rule is over.",
    WARLORD_VOGEL = "The Dustig Oversector is free of its Supreme Moff. Lynch Hauser's rule has collapsed with his "
        .. "last world.",
    WARLORD_WESSEX = "The Relgim Oversector has lost its warlord. Denn Wessex's realm dissolves.",
    WARLORD_CATO_NEIMOIDIA = "Warlord Neimoidia has fallen. Erron Irbian's hold on the Neimoidian purse worlds is "
        .. "broken.",
    WARLORD_KUAT = "The Kuat Sector's warlord has fallen. Thichis Kuras no longer rules the galaxy's greatest "
        .. "shipyards; Kuat will build for new masters.",
    WARLORD_KAARENTH_DISSENSION = "The Kaarenth Dissension is ended. Ennix Devian's rebellion has lost its last "
        .. "world.",
    WARLORD_RESTORED_EMPIRE = "The Restored Empire has fallen. Ennix Devian's promise to bring back the Empire's "
        .. "glory dies with its last world.",
    WARLORD_PRAJI = "Warlord Kaikielius has fallen. Nahdonnis Praji's short rule is over.",
    WARLORD_GRUNGER = "Grunger's Empire is no more. The warlord who defied Zsinj and Teradoc alike has lost his last "
        .. "world.",
    WARLORD_THORN = "Thorn's Empire has fallen. Daymon Thorn's realm is gone.",
}
local BREAKAWAY = "{name} has fallen. The Moff who broke from the Empire to rule alone has lost the last world of "
    .. "the realm he carved out."

local INTEGRATED = {
    ERIADU_AUTHORITY = "The Eriadu Authority signs itself over to {overlord}. Seswenna's bureaucrats change the crest on their letterhead and carry on as the Tarkins taught them.",
    GREATER_MALDROOD = "Greater Maldrood lowers its red banners and sails under {overlord}. Teradoc keeps his crimson hulls, and is told what to do with them.",
    PENTASTAR = "The Pentastar Alignment merges into {overlord}. Ardus Kaine's shareholders vote themselves a new owner and call it a sound investment.",
    ZSINJ_EMPIRE = "Zsinj's empire joins {overlord} in a ceremony he paid for himself. The Iron Fist fires a salute, and everyone wonders who is really giving the orders.",
    CORPORATE_SECTOR = "The Direx Board sells the Corporate Sector's charter to {overlord}. The Espos change their insignia and the invoices keep coming.",
    HAPES_CONSORTIUM = "The Queen Mother binds Hapes to {overlord} by treaty. The Hapan Cluster opens its gates without a shot, for the first time in three thousand years.",
    EMPIREOFTHEHAND = "The Empire of the Hand answers to {overlord} now. Nirauan's officers accept the terms with Thrawn's own unreadable calm.",
    IMPERIAL_PROTEUS = "{name} bends the knee to {overlord}. One more warlord's throne is folded into the Empire's heirs without a shot.",
    YEVETHA = "The Duskhan League submits to {overlord}. Koornacht's fleets stand down, and few believe N'Zoth's people have changed their minds.",
    UNDERWORLD = "{name} comes to terms with {overlord}. Its lieutenants keep their back rooms, and now pay someone else for the privilege.",
    CORELLIA = "Corellia joins {overlord} at last. The proud worlds that always went their own way sign, and grumble about it in every cantina on the Run.",
    CHISS = "The Ruling Families place their holdings here under {overlord}. Csilla says nothing further, and is watching.",
    KILLIK_HIVES = "The Killik Hives join their song to {overlord}. Nobody is entirely sure who has absorbed whom.",
    SSIRUUVI_IMPERIUM = "The Ssi-ruuvi yield their last holdings to {overlord}. The entechment ships go cold under new orders.",
    MANDALORIANS = "The clans take {overlord}'s contract. Mandalorians have served worse paymasters, and they keep their armour on.",
    WARLORD_LAMBDA = "Par Lankin lays his crown at the feet of {overlord}. The Lambda Sector's court at Rintonne bows, and quietly hopes to be forgotten.",
    WARLORD_ZERO_COMMAND = "Blitzer Harrsk swears his fortress worlds to {overlord}. The Whirlwind flies a new flag over the Deep Core, for now.",
    WARLORD_ELROOD = "Villis Andal hands the Elrood Sector to {overlord}, relieved to be somebody else's problem.",
    WARLORD_ANTEMERIDIAS = "Tol Getelles brings the Antemeridian Sector under {overlord}. His garrisons change their orders; the sector's people notice little else.",
    WARLORD_WILD_SPACE = "The Dragon of Wild Space folds his wings. Delurin's Empire is absorbed by {overlord} in a single signing.",
    WARLORD_PRENTIOCH = "Utoxx Prentioch surrenders his Dominion's name and keeps his rank. His worlds are {overlord}'s now.",
    WARLORD_SECTOR_5 = "Malfkla Yzu takes the Constitution's oath to {overlord}. Sector 5 is a line in someone else's ledger now.",
    WARLORD_PRAKITH = "Foga Brill delivers Prakith to {overlord}. The Inquisitor keeps his dungeons, and Prakith's people expect nothing better.",
    WARLORD_JARDEEN = "Iolan Gendarr brings Jardeen and the Reliance into {overlord}. It is the first safe harbour the Reliance has had in years.",
    WARLORD_CIUTRIC_HEGEMONY = "Prince-Admiral Krennel renders the Ciutric Hegemony to {overlord}, loudly calling it an alliance of equals.",
    WARLORD_KAMINO = "The Dark Apprentice opens Kamino's cloning halls to {overlord}. Whatever grows in the vats now grows for a new master.",
    WARLORD_NABOO = "Quarsh Panaka gives Naboo to {overlord} without a battle. The Queen's world keeps its fountains, and loses its say.",
    WARLORD_RADAMA = "Ellor Orgraal places Ord Radama and his fleet under {overlord}, on the promise of a command.",
    WARLORD_TAPANI = "Bal Jaset takes the Tapani Sector into {overlord}. The noble houses begin at once to intrigue against their new masters.",
    WARLORD_GAROS = "Zakar signs Garos over to {overlord}. A realm smaller than his ambitions becomes a province, without a shot.",
    WARLORD_MAELSTROM = "Torpin brings Maelstrom Command in from the storm. Its fleets now sail under {overlord}.",
    WARLORD_SHADOWSPAWN = "Cronal lets the Shadow Realm be absorbed by {overlord}. Those who know Shadowspawn take no comfort in how easily it was done.",
    WARLORD_PROPHETS = "Kadann declares that the Prophets foresaw this. The Sith worlds of the Dark Side's seers are {overlord}'s now.",
    WARLORD_TAGGE = "Ulric Tagge sells the House's sovereignty to {overlord}. The Tagge fortune survives, as it always has.",
    WARLORD_TIERFON = "Supreme Commander Tzenkens hands the Tierfon Sector to {overlord} and is pleased to stay a commander.",
    WARLORD_BAKURA = "Governor Nereus brings Bakura under {overlord}. The Bakurans watch another flag go up over Salis D'aar.",
    WARLORD_BRAK = "Lesan Ramier gives the Brak Sector to {overlord} in return for his life and his title.",
    WARLORD_TAMARIN = "Lobax Resuun calls off his Retribution and swears the Tamarin Sector to {overlord}.",
    WARLORD_ISECTOR = "Bliss Shargael brings the I-sector into {overlord} with a smile and a very long list of conditions.",
    WARLORD_IMPERIAL_LIANNA = "Phillip Santhe gives Lianna to {overlord}. Its shipyards do not miss a single delivery.",
    WARLORD_QUINTAD = "Thalassa Tarkin brings the Quintad into {overlord}. The Tarkin name still opens doors, but no longer its own.",
    WARLORD_DASTA = "Ragez D'Asta turns from raiding to service. The D'Astan Sector belongs to {overlord} now.",
    WARLORD_HAMMERS = "Zel Johans swings the Imperial Hammers behind {overlord}. It is a fleet looking for a cause, and it has found a paymaster.",
    WARLORD_KASHYYYK = "Hindane Darcc gives Kashyyyk to {overlord}. The Wookiees' forests have a new landlord, and no more love for this one.",
    WARLORD_LUMIYA = "Lumiya's Sith bow to {overlord}, for as long as it suits the Dark Lady.",
    WARLORD_ARDA = "Vorrel marches his walkers into {overlord}'s service. Arda changes hands without a shot.",
    WARLORD_SELLASAS = "Jedselk brings Dolla and Sellasas under {overlord} and keeps his chair.",
    WARLORD_PROTECTORATE = "Adalric Brandl folds the Protectorate into {overlord}, sure he will rise to command the lot.",
    WARLORD_ZAARIN_REMNANTS = "Raveen gives up Grand Admiral Zaarin's dream. The Zaarin Remnants sail for {overlord} now.",
    WARLORD_RAYTER = "Nile Owen takes the Rayter Sector into {overlord} and keeps it quiet.",
    WARLORD_VOGEL = "Lynch Hauser gives up the title of Supreme Moff. The Dustig Oversector answers to {overlord}.",
    WARLORD_WESSEX = "Denn Wessex brings the Relgim Oversector under {overlord} and asks only to keep her fleet.",
    WARLORD_CATO_NEIMOIDIA = "Erron Irbian opens the Neimoidian purse worlds to {overlord}. The accounts are transferred by nightfall.",
    WARLORD_KUAT = "Thichis Kuras yields the Kuat Sector to {overlord}. The galaxy's greatest shipyards simply update the customer's name.",
    WARLORD_KAARENTH_DISSENSION = "Ennix Devian ends the Kaarenth Dissension by joining {overlord}, a rebel no longer.",
    WARLORD_RESTORED_EMPIRE = "Ennix Devian's Restored Empire is absorbed by {overlord}. Its promise of old glory is now someone else's.",
    WARLORD_PRAJI = "Nahdonnis Praji gives Kaikielius to {overlord} after a short, nervous rule.",
    WARLORD_GRUNGER = "The warlord who defied Zsinj and Teradoc alike defies no more. Grunger's Empire joins {overlord}.",
    WARLORD_THORN = "Daymon Thorn brings Thorn's Empire under {overlord} without a fight.",
}
local BREAKAWAY_INTEGRATED = "{name} returns to the fold. The Moff who broke away swears fealty to {overlord}, and the realm he carved out goes with him."

local function power(d, faction)
    if FACTIONS.PLAYABLE[faction] or (FACTIONS.MINOR or {})[faction] then
        return true
    end
    local warlords = Diplomacy and Diplomacy.warlord_factions and Diplomacy.warlord_factions() or {}
    return warlords[faction] == true
end

local function holds_world(player)
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == player then
            return true
        end
    end
    return false
end

local function taken_in(d, world, new_owner)
    if not world or not new_owner or not (new_owner == string.upper(d.human.Get_Faction_Name()) or power(d, new_owner)) then
        return false
    end
    local battle = Engine_Battle_Planet and Engine_Battle_Planet()
    return not battle or string.upper(battle) ~= world
end

function Fallen.check(d, old_owner_name, new_owner_name, world)
    local faction = old_owner_name and string.upper(old_owner_name)
    if not faction or faction == string.upper(d.human.Get_Faction_Name()) or not power(d, faction) then
        return
    end
    d.memory.fallen = d.memory.fallen or {}
    if d.memory.fallen[faction] then
        return
    end
    local player = Find_Player(faction)
    if not player or holds_world(player) then
        return
    end
    d.memory.fallen[faction] = true
    local name = d.display_name(faction)
    local new_owner = new_owner_name and string.upper(new_owner_name)
    local text
    if taken_in(d, world, new_owner) then
        text = string.gsub(INTEGRATED[faction] or BREAKAWAY_INTEGRATED, "{overlord}", d.display_name(new_owner))
    else
        text = TEXT[faction] or BREAKAWAY
    end
    text = string.gsub(text, "{name}", name)
    d.show(text, nil, GOLD, 30)
end

return Fallen
