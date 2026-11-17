-- The Imperial Court's lore characters (CourtLore.lua): the Moffs and Grand Moffs of the Imperial powers,
-- the Empire's minor warlords' leaders and the court figures, one entry per character (a hero and its team
-- share the name), with their portraits in the court's frames (icons dp_ip_<name>_g/_s, and _d/_x for the
-- succession row), the generated officers' faces (dp_ip_gen_<n>, i_button_court_officer.tga) and the lore
-- flagships for characters without a ship of the right size (`flags`, Court_Flag_<n>_<rank>, written into
-- Court_Ships.xml by court/ships). `classes`: each court unit's class text (for the hero tooltips).
local lib = gen.load("lib")

local DIR = "Scripts\\Library\\eawx-plugins\\imperial-court\\"
local SUCCESSION = {SATE_PESTAGE = true, YSANNE_ISARD = true, THRAWN_CHIMAERA = true, CARNOR_JAX = true,
                    DAALA_GORGON = true, PELLAEON_CHIMAERA_GRAND = true, EMPEROR_PALPATINE = true, PANAKA_THEED = true}
local FIGURES = {SATE_PESTAGE = true, YSANNE_ISARD = true, ISARD_LUSANKYA = true, HISSA_MOFFSHIP = true,
                 THRAWN_CHIMAERA = true, PELLAEON_CHIMAERA_GRAND = true, PELLAEON_REAPER = true, PELLAEON_MEGADOR = true,
                 DAALA_GORGON = true, DAALA_KNIGHT_HAMMER = true, CARNOR_JAX = true, FLIM_TIERCE_IRONHAND = true,
                 EMPEROR_PALPATINE = true, VORRU = true, VORRU_TEAM = true, PANAKA_THEED = true}
local GENERATED = 6                      -- silhouettes for generated officers
local WEEK_SECONDS = 40                  -- Thrawn's galactic week
local SHADOW_FIELD = {58, 62, 70}

-- the Empire's named heroes by their encyclopedia class: (rank shown at court, branch)
local ROLES = {}
for _, r in ipairs({
        {"Grand Moff", "moff", "GRAND_MOFF_WARLORD GRAND_ADMIRAL_MOFF GRAND_MOFF"},
        {"Moff", "moff", "MOFF"},
        {"Governor", "governor", "GOVERNOR GOVERNOR_GENERAL"},
        {"Grand Admiral", "navy", "GRAND_ADMIRAL"},
        {"Admiral", "navy", "ADMIRAL HIGH_ADMIRAL FLEET_ADMIRAL VICE_ADMIRAL PRINCE_ADMIRAL SUPREME_COMMANDER "
                            .. "FLEET_COMMANDER COMMODORE FLEET_OFFICER"},
        {"Captain", "navy", "CAPTAIN SENIOR_CAPTAIN GROUP_CAPTAIN COMMANDER LIEUTENANT_COMMANDER"},
        {"General", "army", "GENERAL GRAND_GENERAL HIGH_GENERAL SUPERIOR_GENERAL GENERAL_MAJOR BARON_GENERAL "
                            .. "FIELD_COMMANDER"},
        {"Colonel", "army", "COLONEL HIGH_COLONEL MAJOR COMMANDANT"},
        {"Agent", "intel", "INTELLIGENCE DIRECTOR_INTELLIGENCE AGENT AUDITOR_GENERAL"}}) do
    for cls in r[3]:gmatch("%S+") do
        ROLES[cls] = {r[1], r[2]}
    end
end
local RANK_ORDER = {}
for i, rank in ipairs({"Grand Moff", "Moff", "Grand Admiral", "Governor", "Admiral", "General", "Agent", "Captain",
                       "Colonel", ""}) do
    RANK_ORDER[rank] = i
end
-- classes never at court: hired guns, and the anonymous aces and troopers that stand for whole units
local SKIP_CLASSES = {BOUNTY_HUNTER = true, STORYEVENT = true, COMMANDO_SQUAD = true, SLAVER = true, PIRATE = true}
local SKIP_NAMES = {["Imperial Ace"] = true, ["Stormtrooper X"] = true}
local GROUP_WORDS = {}
for w in ("company companies squad squads squadron squadrons platoon platoons battalion battalions legion legions "
          .. "regiment regiments corps troopers commandos guards detachment detachments garrison brigade brigades "
          .. "wing wings team teams crew"):gmatch("%S+") do
    GROUP_WORDS[w] = true
end
-- the Admiralty's ranks and the class of ship a lore flagship of each is (court/ships has the pools)
local SHIP_RANKS = {"G", "M", "V", "S"}
local FLAG_BASE = {G = "IMPERIAL_II_STAR_DESTROYER", M = "IMPERIAL_I_STAR_DESTROYER", V = "STRIKE_CRUISER",
                   S = "ALLEGIANCE_BATTLECRUISER"}

local _, objects, order = lib.objects()
local atlas = lib.atlas()

local function trunc(x)
    return x >= 0 and math.floor(x) or math.ceil(x)
end

-- a field of an object, else of the type it is a variant of (up to `limit` steps)
local function field(obj, tag, limit, depth)
    local entry = objects[obj:upper()]
    depth = depth or 0
    if not entry or depth > (limit or 6) then
        return ""
    end
    local v = entry[2]:match("<" .. tag .. ">%s*([^<]-)%s*</" .. tag .. ">")
    if v and v ~= "" then
        return v
    end
    local parent = entry[2]:match("<Variant_Of_Existing_Type>%s*([^<%s]+)")
    return parent and field(parent, tag, limit, depth + 1) or ""
end

local function text(key)
    return gen.text(key) or ""
end

local function collapse(s)
    local cps = lib.codes(s)
    local out, space = {}, false
    for _, c in ipairs(cps) do
        if lib.is_space(c) then
            space = true
        else
            if space and #out > 0 then
                out[#out + 1] = 32
            end
            space = false
            out[#out + 1] = c
        end
    end
    return #out > 0 and utf8.char(table.unpack(out)) or ""
end

local function words(s)
    local out = {}
    for w in s:gmatch("%S+") do
        out[#out + 1] = w
    end
    return out
end

local function portrait_image(obj)
    local icon = field(obj, "Icon_Name")
    if icon == "" then
        return nil
    end
    if atlas.has(icon) then
        return atlas.icon(icon)
    end
    local src = gen.list(0, "Art\\Textures", icon, false)[1]
    return src and gen.img_convert(gen.img_open(gen.read(0, src)), "RGBA")
end

-- a formation, not a person (a company of troopers, a squadron): just a unit to the court. By its name, or a
-- company whose units are all ordinary troops (no named hero among them)
local function is_group(name, tag, body)
    local cps = lib.codes(name:lower())
    local word = {}
    for i = 1, #cps + 1 do
        local c = cps[i]
        if c and lib.is_word(c) then
            word[#word + 1] = c
        elseif #word > 0 then
            if GROUP_WORDS[utf8.char(table.unpack(word))] then
                return true
            end
            word = {}
        end
    end
    if tag == "HeroCompany" or tag == "GroundCompany" then
        local units = body:match("<Company_Units>%s*([^<]+)")
        local members, heroes = 0, 0
        if units then
            for u in units:gmatch("[^,%s]+") do
                members = members + 1
                local o = objects[u:upper()]
                if o and (o[1] == "HeroUnit" or o[1] == "UniqueUnit") then
                    heroes = heroes + 1
                end
            end
        end
        return members > 0 and heroes == 0
    end
    return false
end

-- the warlords' leaders who count as Imperial Moffs, and the heroes the legitimacy rewards bring in (their
-- groups' units in UnitSwitcherLibrary): they join the court whatever their class or affiliation says
local warlord_leaders = {}
for _, e in ipairs(gen.load("warlords/factions").entries) do
    for _, o in ipairs(e.overrides) do
        if o == "EMPIRE" then
            for _, l in ipairs(e.leaders) do
                warlord_leaders[l] = true
            end
        end
    end
end
local legitimacy = {}
local rewards = gen.read(0, "Scripts\\Library\\eawx-mod-icw\\LegitimacyRewardLibrary.lua")
local switcher = gen.read(0, "Scripts\\Library\\UnitSwitcherLibrary.lua")
if rewards and switcher then
    local groups = {}
    for g in rewards:gmatch("(Dummy_Recruit_Group_[%w_]+)") do
        groups[g:upper()] = true
    end
    for g, list in switcher:gmatch('%["(DUMMY_RECRUIT_GROUP_[%w_]+)"%]%s*=%s*{nil,%s*{([^}]*)}') do
        if groups[g] then
            for u in list:gmatch('"([%w_]+)"') do
                legitimacy[u:upper()] = true
            end
        end
    end
end

-- Every character hero the Empire can field: Imperial heroes of any class, and named heroes of a court class
-- whose affiliation is left to the campaign scripts (Independent_Forces: many fleet commanders are handed to
-- a faction by story events). A hero only joins the court while the Empire owns its unit.
local chars, classes = {}, {}
for _, obj in ipairs(order) do
    local tag, body = objects[obj][1], objects[obj][2]
    if tag == "HeroUnit" or tag == "HeroCompany" or tag == "UniqueUnit" or tag == "GroundCompany" then
        local class_id = field(obj, "Encyclopedia_Unit_Class")
        local cls = (class_id ~= "" and class_id or body):match("TEXT_ENCYCLOPEDIA_CLASS_([A-Z_]+)")
        local figure, leader = FIGURES[obj] == true, warlord_leaders[obj] == true
        local role = cls and ROLES[cls]
        local affiliation = field(obj, "Affiliation"):upper()
        local imperial = (" " .. affiliation .. " "):find("[ ,]EMPIRE[ ,]") ~= nil
        local named = field(obj, "Is_Named_Hero"):lower() == "yes"
        local keep = true
        if not (figure or leader or legitimacy[obj]) then
            if cls and SKIP_CLASSES[cls] then
                keep = false
            elseif role and not (imperial or affiliation:find("INDEPENDENT_FORCES", 1, true)) then
                keep = false
            elseif not role and not (imperial and named) then
                keep = false
            elseif role and role[2] ~= "moff" and role[2] ~= "governor" and not named then
                keep = false
            end
        end
        local name = keep and lib.strip(collapse(text(field(obj, "Text_ID"):upper()))):gsub('"', "'") or ""
        if keep and name ~= "" and not SKIP_NAMES[name] and (figure or not is_group(name, tag, body)) then
            local class_text = class_id ~= "" and lib.strip(text(lib.strip(class_id):upper())) or ""
            if class_text ~= "" then
                classes[obj] = class_text
            end
            local rank, branch = "", "figure"
            if role then
                rank, branch = role[1], role[2]
            end
            -- officers whose command is on the ground ("Command Tier N (Land)") are Army, whatever the class says
            local bio = {}
            for i, t in ipairs(words(field(obj, "Encyclopedia_Text"))) do
                if i > 3 then break end
                bio[#bio + 1] = text(t:upper())
            end
            bio = table.concat(bio, " ")
            if branch == "navy" and bio:find("(Land)", 1, true) and not bio:find("(Space)", 1, true) then
                branch = "army"
            end
            if leader and not role then
                rank, branch = "Moff", "moff"
            end
            local entry = chars[name]
            if not entry then
                entry = {rank = "", role = "", units = {}, figure = false, warlord = false, space = false, title = "",
                         class = ""}
                chars[name] = entry
            end
            if cls and (entry.class == "" or role and not ROLES[entry.class]) then
                entry.class = cls
            end
            local mask = field(obj, "CategoryMask")
            for _, k in ipairs({"SpaceHero", "Capital", "Frigate", "Corvette", "Fighter", "Bomber"}) do
                if mask:find(k, 1, true) then
                    entry.space = true
                end
            end
            if not role and entry.title == "" and class_text ~= "" then
                entry.title = class_text
            end
            if rank ~= "" and RANK_ORDER[rank] < RANK_ORDER[entry.rank] then
                entry.rank, entry.role = rank, branch
            end
            entry.units[#entry.units + 1] = obj
            entry.figure = entry.figure or figure
            entry.warlord = entry.warlord or leader
        end
    end
end

-- a ship's size class from its base type (heroes' own masks only say SpaceHero)
local function ship_size(obj, depth)
    local entry = objects[obj:upper()]
    depth = depth or 0
    if not entry or depth > 10 then
        return nil
    end
    local m = entry[2]:match("<CategoryMask>%s*([^<]*)</CategoryMask>")
    if m and not m:find("Hero", 1, true) then
        local parts = {}
        for p in m:gmatch("[^|]+") do
            parts[lib.strip(p)] = true
        end
        for _, k in ipairs({"SuperCapital", "Capital", "Frigate", "Corvette", "Fighter", "Bomber"}) do
            if parts[k] then
                return k
            end
        end
    end
    local parent = entry[2]:match("<Variant_Of_Existing_Type>%s*([^<%s]+)")
    return parent and ship_size(parent, depth + 1) or nil
end

local function weeks_of(obj)
    local seconds = tonumber(field(obj, "Build_Time_Seconds")) or 0
    return math.max(1, lib.round(seconds / WEEK_SECONDS))
end

local function lua_text(value)
    return (value:gsub("\\", ""):gsub('"', "'"):gsub("\n", "\\n"))
end

-- the commands and stats part of each court ship's tooltip (Thrawn's generic commander of that class)
local ship_blocks = {}
for _, rank in ipairs(SHIP_RANKS) do
    local tokens = {}
    for _, obj in ipairs(order) do
        local tag, body = objects[obj][1], objects[obj][2]
        local v = body:match("<Variant_Of_Existing_Type>%s*([^<%s]+)")
        if tag == "GenericCommander" and v and v:upper() == FLAG_BASE[rank] then
            tokens = words(body:match("<Encyclopedia_Text>([^<]*)</Encyclopedia_Text>") or "")
            break
        end
    end
    for k, t in ipairs(tokens) do
        if t:upper() == "TEXT_TOOLTIP_SEPARATOR_COMMANDS_BLOCK" then
            tokens = {table.unpack(tokens, k)}
            break
        end
    end
    ship_blocks[rank] = tokens
end

-- portraits: the face in a rounded frame (the mod's, drawn by the build: frame layers and masks)
local FACE_MASK = lib.data_image("court_face_mask", "L")
local FRAME_MASK = lib.data_image("court_frame_mask", "L")
local FRAMES = {g = lib.data_image("court_frame_g"), s = lib.data_image("court_frame_s"),
                n = lib.data_image("court_frame_n")}

local function court_portrait(img, frame)
    local im = gen.img_new("RGBA", 64, 64, 0, 0, 0, 0)
    local face = gen.img_resize(gen.img_convert(img, "RGBA"), 54, 54, "lanczos")
    gen.img_paste(im, face, 5, 5, FACE_MASK)
    gen.img_paste(im, FRAMES[frame], 0, 0, FRAME_MASK)
    return im
end

local function lut(fn)
    local out = {}
    for v = 0, 255 do
        out[v + 1] = string.char(math.max(0, math.min(255, fn(v))))
    end
    return table.concat(out)
end

-- ImageOps.autocontrast (no cutoff) of a one band image
local function autocontrast(im)
    local h = gen.img_histogram(im)
    local lo, hi = 0, 255
    while lo < 255 and h[lo + 1] == 0 do lo = lo + 1 end
    while hi > 0 and h[hi + 1] == 0 do hi = hi - 1 end
    if hi <= lo then
        return gen.img_point(im, lut(function(v) return v end))
    end
    local scale = 255.0 / (hi - lo)
    local offset = -lo * scale
    return gen.img_point(im, lut(function(v) return trunc(v * scale + offset) end))
end

local icons = {}
local lua = {"return {", "    CHARACTERS = {"}
local flags, flag_no, count = {}, 0, 0
for _, name in ipairs(lib.sorted_keys(chars)) do
    local c = chars[name]
    local units = {table.unpack(c.units)}
    local position = {}
    for i, u in ipairs(units) do position[u] = i end
    table.sort(units, function(a, b)
        local ta, tb = a:sub(-5) == "_TEAM", b:sub(-5) == "_TEAM"
        if ta ~= tb then return tb end
        if #a ~= #b then return #a < #b end
        return position[a] < position[b]
    end)
    local in_succession = false
    for _, u in ipairs(units) do
        if SUCCESSION[u] then in_succession = true end
    end
    local img
    for _, u in ipairs(units) do
        img = portrait_image(u)
        if img then break end
    end
    local base = "dp_ip_" .. name:lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if img then
        icons[base .. "_g.tga"] = court_portrait(img, "g")
        icons[base .. "_s.tga"] = court_portrait(img, "s")
        if in_succession then
            -- the succession row: "_d" a past ruler (slightly greyed), "_x" one still to come (a silhouette)
            local rgba = gen.img_convert(img, "RGBA")
            local grey = gen.img_convert(gen.img_convert(gen.img_convert(img, "RGB"), "L"), "RGBA")
            local faded = gen.img_blend(rgba, grey, 0.55)
            local w, h = gen.img_size(faded)
            faded = gen.img_blend(faded, gen.img_new("RGBA", w, h, 40, 42, 48, 255), 0.25)
            local _, _, _, alpha = gen.img_split(rgba)
            gen.img_putalpha(faded, alpha)
            icons[base .. "_d.tga"] = court_portrait(faded, "s")
            local shade = autocontrast(gen.img_convert(gen.img_convert(img, "RGB"), "L"))
            local bands = {}
            for i, k in ipairs({0.16, 0.18, 0.24}) do
                bands[i] = gen.img_point(shade, lut(function(v) return trunc(10 + v * k) end))
            end
            icons[base .. "_x.tga"] = court_portrait(gen.img_convert(gen.img_merge("RGB", bands), "RGBA"), "n")
        end
    else
        base = "dp_ip_lore"
    end
    local kind = c.figure and "figure" or (c.warlord and "warlord" or (c.role ~= "" and c.role or "moff"))
    local rank = (c.rank ~= "" and c.rank or c.title):gsub('"', "'")
    local bio = ""
    if in_succession then
        -- the rulers' own hero tooltips (traits and biography; not the ship's stats) for the succession row
        for _, u in ipairs(units) do
            local lines, keep = {}, false
            for _, token in ipairs(words(field(u, "Encyclopedia_Text"))) do
                local t = token:upper()
                if t:sub(1, 23) == "TEXT_TOOLTIP_SEPARATOR_" then
                    keep = t == "TEXT_TOOLTIP_SEPARATOR_TRAITS_BLOCK" or t == "TEXT_TOOLTIP_SEPARATOR_BIO_BLOCK"
                        or t == "TEXT_TOOLTIP_SEPARATOR_COMMANDS_BLOCK"
                elseif keep and text(t) ~= "" then
                    lines[#lines + 1] = lib.strip(collapse(text(t)))
                end
            end
            if #lines > 0 then
                for i, l in ipairs(lines) do lines[i] = l:gsub("%.+$", "") end
                bio = table.concat(lines, ". ") .. "."
                break
            end
        end
    end
    bio = bio:gsub("\\", ""):gsub('"', "'")
    -- the Admiralty: their own ship when it is a frigate or a Star Destroyer, else a court ship of the rank's
    -- class with their portrait and tooltip (types Court_Flag_<n>_<G|M|V|S>)
    local main = units[1]
    for _, u in ipairs(units) do
        if field(u, "Icon_Name") ~= "" then main = u break end
    end
    local own
    for _, u in ipairs(units) do
        local size = ship_size(u)
        if size == "Frigate" or size == "Capital" then own = u break end
    end
    local extra = ""
    if own then
        local price = math.floor(tonumber(field(own, "Build_Cost_Credits")) or 0)
        if price == 0 then price = 3000 end
        extra = extra .. string.format(', ship = "%s", ship_price = %d, ship_weeks = %d', own, price, weeks_of(own))
    else
        flag_no = flag_no + 1
        local flag = "Court_Flag_" .. flag_no
        local hero_tokens = words(field(main, "Encyclopedia_Text"))
        for k, t in ipairs(hero_tokens) do
            if t:upper() == "TEXT_TOOLTIP_SEPARATOR_COMMANDS_BLOCK" then
                hero_tokens = {table.unpack(hero_tokens, 1, k - 1)}
                break
            end
        end
        for _, rank_key in ipairs(SHIP_RANKS) do
            local base_ship = FLAG_BASE[rank_key]
            local mask = field(base_ship, "CategoryMask")
            if mask == "" then mask = "Capital" end
            local parts = {"SpaceHero"}
            for piece in mask:gmatch("[^|]+") do
                local p = lib.strip(piece)
                if p ~= "" and p ~= "SpaceHero" then parts[#parts + 1] = p end
            end
            local tokens = {}
            for _, t in ipairs(hero_tokens) do tokens[#tokens + 1] = "\t\t" .. t end
            for _, t in ipairs(ship_blocks[rank_key]) do tokens[#tokens + 1] = "\t\t" .. t end
            local cls = field(main, "Encyclopedia_Unit_Class")
            flags[#flags + 1] = "\t<UniqueUnit Name=\"" .. flag .. "_" .. rank_key .. "\">\n"
                .. "\t\t<Variant_Of_Existing_Type>" .. base_ship .. "</Variant_Of_Existing_Type>\n"
                .. "\t\t<Is_Named_Hero>Yes</Is_Named_Hero>\n"
                .. "\t\t<Text_ID>" .. field(main, "Text_ID") .. "</Text_ID>\n"
                .. "\t\t<Encyclopedia_Text>\n"
                .. "\t\t" .. lib.strip(table.concat(tokens, "\n")) .. "\n"
                .. "\t\t</Encyclopedia_Text>"
                .. (cls ~= "" and "\n\t\t<Encyclopedia_Unit_Class>" .. cls .. "</Encyclopedia_Unit_Class>" or "")
                .. "\n\t\t<CategoryMask> " .. table.concat(parts, " | ") .. " </CategoryMask>\n"
                .. "\t\t<Tech_Level>99</Tech_Level>\n"
                .. "\t\t<Icon_Name>" .. field(main, "Icon_Name") .. "</Icon_Name>\n"
                .. "\t\t<Show_Hero_Head>Yes</Show_Hero_Head>\n"
                .. "\t\t<Is_Sellable>Sellable_Never</Is_Sellable>\n"
                .. "\t\t<Affiliation>Independent_Forces</Affiliation>\n"
                .. "\t</UniqueUnit>"
        end
        extra = extra .. string.format(', flag = "%s"', flag:upper())
    end
    local tip = {}
    for _, t in ipairs(words(field(main, "Encyclopedia_Text"))) do
        local line = lib.strip(collapse(text(t:upper())))
        if line ~= "" then tip[#tip + 1] = line end
    end
    if #tip > 0 then
        extra = extra .. ', tip = "' .. lua_text(table.concat(tip, "\n")) .. '"'
    end
    local quoted = {}
    for i, u in ipairs(units) do quoted[i] = '"' .. u .. '"' end
    lua[#lua + 1] = string.format('        {name = "%s", rank = "%s", role = "%s", kind = "%s", portrait = "%s", units = {%s}',
                                  name, rank, c.role ~= "" and c.role or "figure", kind, base, table.concat(quoted, ", "))
        .. (c.space and ", space = true" or "") .. (c.class ~= "" and ', class = "' .. c.class .. '"' or "")
        .. (bio ~= "" and ', bio = "' .. bio .. '"' or "") .. extra .. "},"
    count = count + 1
end
lua[#lua + 1] = "    },"
lua[#lua + 1] = "    FLAGS = {"
for _, rank_key in ipairs(SHIP_RANKS) do
    local base_ship = FLAG_BASE[rank_key]
    lua[#lua + 1] = string.format("        %s = {price = %d, weeks = %d},", rank_key,
                                  math.floor(tonumber(field(base_ship, "Build_Cost_Credits")) or 0), weeks_of(base_ship))
end
lua[#lua + 1] = "    },"
lua[#lua + 1] = "    CLASSES = {"
local used = {}
for _, c in pairs(chars) do
    for _, u in ipairs(c.units) do used[u] = true end
end
local court_classes = {}
for _, unit in ipairs(lib.sorted_keys(classes)) do
    if used[unit] then
        lua[#lua + 1] = string.format('        %s = "%s",', unit, (classes[unit]:gsub('"', "'")))
        court_classes[unit] = classes[unit]
    end
end
lua[#lua + 1] = "    },"
lua[#lua + 1] = "}"

-- generated officers (placeholders): the Imperial Kashyyyk leader's portrait as a black silhouette
local darcc = atlas.icon("I_Button_Darcc.tga")
if not darcc then
    local src = gen.list(0, "Art\\Textures", "I_Button_Darcc.tga", false)[1]
    darcc = src and gen.img_convert(gen.img_open(gen.read(0, src)), "RGBA")
end
local shadow
if darcc then
    local figure = gen.img_resize(gen.img_convert(darcc, "RGBA"), 64, 64, "lanczos")
    local _, _, _, alpha = gen.img_split(figure)
    shadow = gen.img_new("RGBA", 64, 64, SHADOW_FIELD[1], SHADOW_FIELD[2], SHADOW_FIELD[3], 255)
    local cut = lut(function(a) return a > 60 and 255 or 0 end)
    gen.img_paste(shadow, gen.img_new("RGBA", 64, 64, 120, 124, 134, 255), 0, 0, gen.img_point(alpha, cut))
    gen.img_paste(shadow, gen.img_new("RGBA", 64, 64, 8, 8, 10, 255), 0, 0,
                  gen.img_rankfilter(gen.img_point(alpha, cut), 3, 0))
else
    shadow = lib.data_image("court_silhouette_1")
end
for k = 1, GENERATED do
    icons["dp_ip_gen_" .. k .. ".tga"] = court_portrait(shadow, "n")
end
-- the flagships' hero head: the figure and its rim on a transparent field, 50 x 50 like Thrawn's hero icons
local raw = gen.img_bytes(shadow)
local out = {}
for i = 1, #raw, 4 do
    local r, g, b = raw:byte(i, i + 2)
    out[#out + 1] = (r == SHADOW_FIELD[1] and g == SHADOW_FIELD[2] and b == SHADOW_FIELD[3]) and "\0\0\0\0"
                    or raw:sub(i, i + 3)
end
local head = gen.img_copy(shadow)
gen.img_set_bytes(head, table.concat(out))
icons["i_button_court_officer.tga"] = gen.img_resize(head, 50, 50, "lanczos")

return {
    [DIR .. "CourtLore.lua"] = lib.latin1(lib.lines(lua)),
    icons = icons, flags = flags, classes = court_classes, count = count,
}
