-- DiplomacyLeaders.lua: the leaders the Diplomacy window shows, from Thrawn's heroes:
-- {FACTION = {{type, name, icon}, ...}, CHIEFS = {type = {name, icon}}, WARLORDS = {[display name] = {...}},
-- HEROES = {type = {name, icon, value}}}. A portrait that is not in Thrawn's command bar atlas is added to the mod's
-- (icons, from Thrawn's loose texture).
local lib = gen.load("lib")

local LEADERS = {
    {"EMPIRE", {"SATE_PESTAGE", "YSANNE_ISARD", "ISARD_LUSANKYA", "HISSA_MOFFSHIP", "THRAWN_CHIMAERA",
                "FLIM_TIERCE_IRONHAND", "EMPEROR_PALPATINE", "CARNOR_JAX", "DAALA_GORGON", "DAALA_KNIGHT_HAMMER",
                "PELLAEON_CHIMAERA_GRAND", "PELLAEON_REAPER", "PELLAEON_MEGADOR"}},
    {"PENTASTAR", {"ARDUS_KAINE", "KAINE_REAPER"}},
    {"GREATER_MALDROOD", {"TREUTEN_13X", "TREUTEN_CRIMSON_SUNRISE", "KOSH_LANCET"}},
    {"ZSINJ_EMPIRE", {"ZSINJ_IRON_FIST_VSD", "ZSINJ_IRON_FIST_EXECUTOR"}},
    {"ERIADU_AUTHORITY", {"DELVARDUS_BRILLIANT", "DELVARDUS_THALASSA", "DELVARDUS_NIGHT_HAMMER"}},
    {"HUTT_CARTELS", {"DURGA_DARKSABER", "BORVO_PROSPEROUS_SECRET"}},
    {"CORPORATE_SECTOR", {"ODUMIN"}},
    {"HAPES_CONSORTIUM", {"TAA_CHUME_STAR_HOME", "ISOLDER_SONG_OF_WAR", "TENENIEL_DJO"}},
    {"EMPIREOFTHEHAND", {"PARCK_STRIKEFAST", "PARCK_CHAF_DESTROYER", "PRENTIOCH_PRENTIOCH"}},
    {"YEVETHA", {"SPAAR_ARAMADIA", "SPAAR_ARAMADIA_SSD"}},
}
-- portraits for leaders whose every entry is a flagship (must be in Thrawn's command bar atlas)
local PORTRAITS = {DURGA_DARKSABER = "I_BUTTON_DURGA.TGA"}
local CHIEFS = {"DUMMY_CHIEFOFSTATE_MOTHMA", "DUMMY_CHIEFOFSTATE_ORGANA_SOLO", "DUMMY_CHIEFOFSTATE_FEYLYA",
                "DUMMY_CHIEFOFSTATE_GAVRISOM", "DUMMY_CHIEFOFSTATE_KERRITHRARR", "DUMMY_CHIEFOFSTATE_SHESH",
                "DUMMY_CHIEFOFSTATE_SOBILLES", "DUMMY_CHIEFOFSTATE_TEVV"}
local HERO_TAGS = {HeroUnit = true, HeroCompany = true, GenericHeroUnit = true, FlagshipUnit = true, UniqueUnit = true}
-- who speaks for a faction whose own leader isn't there: its hero of the highest standing by encyclopedia class
-- (rulers first, agents and hired guns last; any other class 2), then the most valuable
local STANDING = {}
for _, r in ipairs({
        {6, "GRAND_MOFF_WARLORD GRAND_MOFF GRAND_ADMIRAL_MOFF WARLORD EMPEROR KING QUEEN ROYAL_HOME CHIEF_OF_STATE"},
        {5, "MOFF GOVERNOR GOVERNOR_GENERAL GRAND_ADMIRAL SUPREME_COMMANDER"},
        {4, "ADMIRAL HIGH_ADMIRAL FLEET_ADMIRAL VICE_ADMIRAL PRINCE_ADMIRAL GRAND_GENERAL HIGH_GENERAL SUPERIOR_GENERAL"},
        {3, "GENERAL GENERAL_MAJOR BARON_GENERAL FIELD_COMMANDER FLEET_COMMANDER COMMODORE"},
        {1, "DARK_JEDI INQUESTOR JEDI_KNIGHT SITHSPAWN"},
        {0, "INTELLIGENCE DIRECTOR_INTELLIGENCE AGENT AUDITOR_GENERAL BOUNTY_HUNTER SMUGGLER PIRATE SLAVER COMMANDO "
            .. "ELITE_COMMANDO STORYEVENT PROBE"}}) do
    for cls in r[2]:gmatch("%S+") do
        STANDING[cls] = r[1]
    end
end

local _, objects = lib.objects()
local atlas = lib.atlas()

local function field(obj, tag, depth)
    local entry = objects[obj:upper()]
    depth = depth or 0
    if not entry or depth > 6 then
        return ""
    end
    local v = entry[2]:match("<" .. tag .. ">%s*([^<]-)%s*</" .. tag .. ">")
    if v and v ~= "" then
        return v
    end
    local parent = entry[2]:match("<Variant_Of_Existing_Type>%s*([^<%s]+)")
    return parent and field(parent, tag, depth + 1) or ""
end

-- Python's str.title() on ASCII
local function title(s)
    local prev = false
    return (s:gsub(".", function(c)
        local letter = c:find("%a") ~= nil
        local out = letter and (prev and c:lower() or c:upper()) or c
        prev = letter
        return out
    end))
end

local function collapse(s)
    local cps, out, space = lib.codes(s), {}, false
    for _, c in ipairs(cps) do
        if lib.is_space(c) then
            space = true
        else
            if space and #out > 0 then out[#out + 1] = 32 end
            space = false
            out[#out + 1] = c
        end
    end
    return #out > 0 and utf8.char(table.unpack(out)) or ""
end

-- every case-insensitive `word` (and, with `also`, an `also` right after it) replaced by `repl`
local function replace_ci(s, word, repl, also)
    local low, lw, la = s:lower(), word:lower(), also and also:lower()
    local out, pos = {}, 1
    while true do
        local a, b = low:find(lw, pos, true)
        if not a then break end
        if la and low:sub(b + 1, b + #la) == la then
            b = b + #la
        end
        out[#out + 1] = s:sub(pos, a - 1) .. repl
        pos = b + 1
    end
    out[#out + 1] = s:sub(pos)
    return table.concat(out)
end

local function loose(icon)
    return gen.list(0, "Art\\Textures", icon, false)[1]
end

local function exists(icon)
    return atlas.has(icon) or loose(icon) ~= nil
end

-- the portrait without a role badge: "_ADMIN" (gear) and "_SPYMASTER" (magnifier) variants carry one in the
-- corner; the plain or "_LEADER" portrait of the same character is used when it exists
local function unbadged(icon)
    for _, badge in ipairs({"_ADMIN", "_SPYMASTER"}) do
        if icon:upper():find(badge, 1, true) then
            for _, candidate in ipairs({replace_ci(icon, badge, ""), replace_ci(icon, badge, "_LEADER", "_LEADER")}) do
                if exists(candidate) then
                    return unbadged(candidate)
                end
            end
        end
    end
    return icon
end

local icons = {}
local function entry(obj, icon_from)
    local icon = field(icon_from or obj, "Icon_Name")
    if icon == "" then
        return nil
    end
    icon = unbadged(icon)
    if not atlas.has(icon) then
        local src = loose(icon)
        if not src then
            return nil
        end
        icons[icon:lower()] = gen.img_resize(gen.img_convert(gen.img_open(gen.read(0, src)), "RGBA"), 64, 64)
        icon = icon:lower()
    end
    local name = gen.text(field(obj, "Text_ID"):upper())
    if name == nil then
        name = title((obj:gsub("_", " ")))
    end
    name = lib.strip(collapse(name))
    return {(name:gsub('"', "'")), icon}
end

local lines = {"return {"}
local found = 0
for _, leaders in ipairs(LEADERS) do
    local faction, types = leaders[1], leaders[2]
    local entries, portraits, rows = {}, {}, {}
    for i, obj in ipairs(types) do
        entries[i] = entry(obj) or false
    end
    -- a leader on a flagship variant (icon "..._SSD") shows his portrait from another entry of his
    for _, e in ipairs(entries) do
        if e and e[2]:upper():sub(-8) ~= "_SSD.TGA" then
            portraits[e[1]] = e[2]
        end
    end
    for i, obj in ipairs(types) do
        local e = entries[i]
        if e then
            local icon = PORTRAITS[obj] or portraits[e[1]] or e[2]
            -- the spymaster versions carry a magnifying glass: use the plain portrait when there is one
            local plain = replace_ci(icon, "_SPYMASTER", "")
            if plain ~= icon and atlas.has(plain) then
                icon = plain
            end
            rows[#rows + 1] = string.format('{type = "%s", name = "%s", icon = "%s"}', obj, e[1], icon)
            found = found + 1
        end
    end
    lines[#lines + 1] = "    " .. faction .. " = {" .. table.concat(rows, ", ") .. "},"
end
local rows = {}
for _, obj in ipairs(CHIEFS) do
    local e = entry(obj, "CANDIDATE_" .. obj:sub(#"DUMMY_CHIEFOFSTATE_" + 1))
    if e then
        rows[#rows + 1] = string.format('%s = {name = "%s", icon = "%s"}', obj, e[1], e[2])
        found = found + 1
    end
end
lines[#lines + 1] = "    CHIEFS = {" .. table.concat(rows, ", ") .. "},"

-- Warlords a campaign puts in a faction's slot (Thrawn's ProteusWarlordLibrary: Lambda Sector, Imperial Kamino,
-- The Protectorate...): by display name, their leaders (LeaderTable: a hero, or team -> units; the team and its
-- units are all tried, since the galaxy shows the team)
local library = gen.read(0, "Scripts\\Library\\ProteusWarlordLibrary.lua")
local starts = {}
for s, name, e in library:gmatch('()FriendlyName%s*=%s*"([^"]+)"()') do
    starts[#starts + 1] = {s, name, e}
end
rows = {}
for i, st in ipairs(starts) do
    local segment = library:sub(st[3], starts[i + 1] and starts[i + 1][1] - 1 or #library)
    local _, open_end = segment:find("LeaderTable%s*=%s*{")
    local table_text
    if open_end then
        local q = open_end
        while true do
            q = segment:find("}", q + 1, true)
            if not q then break end
            local ws = segment:match("^%s*,(%s*)", q + 1)
            if ws and ws:find("\n", 1, true) then
                table_text = segment:sub(open_end + 1, q - 1)
                break
            end
        end
    end
    if table_text then
        local names, seen, leaders = {}, {}, {}
        for n in table_text:gmatch('"([%w_]+)"') do names[#names + 1] = n end
        for n in table_text:gmatch('%["([%w_]+)"%]') do names[#names + 1] = n end
        for _, n in ipairs(names) do
            local obj = n:upper()
            if not seen[obj] and obj ~= "NO_LEGITIMACY" then
                seen[obj] = true
                local e = entry(obj)
                if e then
                    leaders[#leaders + 1] = string.format('{type = "%s", name = "%s", icon = "%s"}', obj, e[1], e[2])
                end
            end
        end
        if #leaders > 0 then
            rows[#rows + 1] = '        ["' .. st[2] .. '"] = {' .. table.concat(leaders, ", ") .. "},"
            if st[2]:sub(1, 9) == "Imperial " then     -- the same warlord on its own: "Warlord Kashyyyk"
                rows[#rows + 1] = '        ["Warlord ' .. st[2]:sub(10) .. '"] = {' .. table.concat(leaders, ", ") .. "},"
            end
            found = found + #leaders
        end
    end
end
-- every lore warlord's own leader (Thrawn's warlord factions' LeaderTable)
local warlord_leader = {}
for _, e in ipairs(gen.load("warlords/factions").entries) do
    for _, obj in ipairs(e.leaders or {}) do
        warlord_leader[obj:upper()] = true
    end
end
lines[#lines + 1] = "    WARLORDS = {"
for _, r in ipairs(rows) do lines[#lines + 1] = r end
lines[#lines + 1] = "    },"

-- every hero with a portrait already in Thrawn's atlas: the window's last resort when a faction has none of its
-- listed leaders (e.g. Eriadu in Lambda Sector): its most valuable hero speaks for it
lines[#lines + 1] = "    HEROES = {"
local names = {}
for name in pairs(objects) do names[#names + 1] = name end
table.sort(names)
for _, obj in ipairs(names) do
    local tag, body = objects[obj][1], objects[obj][2]
    local ok = HERO_TAGS[tag]
    if ok and (tag == "FlagshipUnit" or tag == "UniqueUnit") then
        local v = body:lower():match("<is_hero>%s*(%a*)") or ""
        ok = v:sub(1, 3) == "yes" or v:sub(1, 4) == "true"
    end
    if ok then
        local icon = unbadged(field(obj, "Icon_Name"))
        if icon ~= "" and atlas.has(icon) and obj:find("^[A-Z_][A-Z0-9_]*$") then
            local cost = body:match("<Build_Cost_Credits>%s*(%d+)")
            local cls = field(obj, "Encyclopedia_Unit_Class"):match("TEXT_ENCYCLOPEDIA_CLASS_([A-Z_]+)")
            local rank = (warlord_leader[obj] and 7) or (cls and STANDING[cls]) or 2
            local name = gen.text(field(obj, "Text_ID"):upper())
            if name == nil then
                name = title((obj:gsub("_", " ")))
            end
            name = lib.strip(collapse(name)):gsub('"', "'")
            lines[#lines + 1] = string.format('        %s = {name = "%s", icon = "%s", value = %s, rank = %d},', obj, name,
                                              icon, cost or "0", rank)
        end
    end
end
lines[#lines + 1] = "    },"
lines[#lines + 1] = "}"

return {["Scripts\\Library\\eawx-plugins\\diplomacy\\DiplomacyLeaders.lua"] = lib.latin1(lib.lines(lines)),
        icons = icons, count = found}
