-- The factions' emblems for the Diplomacy window, from Thrawn's ally crests (Thrawn's GameConstants
-- PARTICLES: faction -> particle -> model -> p_allied_* texture):
--   icons dp_emblem_<faction>.tga, dp_crest_<particle>.tga (every other ally crest, e.g. campaign
--   warlords' own), dp_emblem_warlord_<key>.tga and dp_emblem_breakaway_<n>.tga (the warlord's crest,
--   else the Imperial one in grey), dp_vassal_<faction>.tga (the faded vassal crest)
--   Art\Textures\p_vassal_*.tga: the vassal markers' textures, a faded grey copy of the ally texture
--   DiplomacyCrests.lua: particle -> crest icon
local lib = gen.load("lib")

local function find(folder, name)
    return gen.list(0, folder, name, false)[1]
end

local particles = gen.read(0, "XML\\Particles\\Particles_Galactic.xml")
local constants = gen.read(0, "Scripts\\Library\\eawx-mod-icw\\GameConstants.lua")
local faction_particles = {}
for f, p in constants:match("PARTICLES%s*=%s*{(.-)}"):gmatch('([A-Z_]+)%s*=%s*"([A-Za-z_]+)"') do
    faction_particles[#faction_particles + 1] = {f, p}
end

-- the texture an ally crest model shows (p_allied_*.tga / p_allies_*.tga, any case)
local function model_texture(model)
    local data = gen.read(0, model)
    local s, e = data:lower():find("p_allie[ds]_[a-z0-9_]+%.tga")
    return s and data:sub(s, e)
end

local function particle_model(particle)
    local body = particles:match('<Particle Name="' .. particle .. '">(.-)</Particle>')
    local name = body and body:match("<Galactic_Model_Name>%s*([^<%s]+)%s*</Galactic_Model_Name>")
    return name and find("Art\\Models", name)
end

local icons, outputs, done = {}, {}, {}
for _, fp in ipairs(faction_particles) do
    local faction, particle = fp[1], fp[2]
    local model = particle_model(particle)
    local texture = model and model_texture(model)
    local source = texture and find("Art\\Textures", texture)
    if source then
        local img = gen.img_convert(gen.img_open(gen.read(0, source)), "RGBA")
        icons["dp_emblem_" .. faction:lower() .. ".tga"] = gen.img_resize(img, 64, 64, "lanczos")
        -- faded and greyed toward a light grey: the vassal's version of the crest
        local raw = gen.img_bytes(img)
        local out = {}
        for i = 1, #raw, 4 do
            local r, g, b, a = raw:byte(i, i + 3)
            local grey = 0.30 * r + 0.59 * g + 0.11 * b
            local function mix(c)
                return math.max(0, math.min(255, lib.round(c * 0.25 + grey * 0.75 + 40)))
            end
            out[#out + 1] = string.char(mix(r), mix(g), mix(b), a)
        end
        gen.img_set_bytes(img, table.concat(out))
        icons["dp_vassal_" .. faction:lower() .. ".tga"] = gen.img_resize(img, 64, 64, "lanczos")
        outputs["Art\\Textures\\p_vassal_" .. texture:sub(10)] = gen.img_tga(img)
        done[#done + 1] = faction
    end
end

-- every other ally crest (campaign warlords' own, e.g. Kaarenth_Allies), by particle name
local base = {}
for _, fp in ipairs(faction_particles) do
    base[fp[2]:lower()] = true
end
local crests, crest_of = {}, {}
for name, body in particles:gmatch('<Particle Name="([A-Za-z0-9_]+_Allies)">(.-)</Particle>') do
    local particle = name:lower()
    if not base[particle] then
        local model_name = body:match("<Galactic_Model_Name>%s*([^<%s]+)%s*</Galactic_Model_Name>")
        local model = model_name and find("Art\\Models", model_name)
        local texture = model and model_texture(model)
        local source = texture and find("Art\\Textures", texture)
        if source then
            local icon = "dp_crest_" .. particle .. ".tga"
            icons[icon] = gen.img_resize(gen.img_convert(gen.img_open(gen.read(0, source)), "RGBA"), 64, 64, "lanczos")
            crests[#crests + 1] = string.format('    %s = "%s",', particle, icon)
            crest_of[particle] = icon
        end
    end
end

-- the minor warlords' own factions and the breakaway slots: the warlord's crest where Thrawn has one, else
-- the Imperial crest in grey (a remnant of the Empire)
local imperial = icons["dp_emblem_empire.tga"]
if imperial then
    local grey = gen.img_blend(gen.img_convert(imperial, "RGBA"),
                               gen.img_convert(gen.img_convert(gen.img_convert(imperial, "RGB"), "L"), "RGBA"), 0.85)
    local _, _, _, alpha = gen.img_split(gen.img_convert(imperial, "RGBA"))
    gen.img_putalpha(grey, alpha)
    local warlords = gen.load("warlords/factions")
    for _, e in ipairs(warlords.entries) do
        icons["dp_emblem_warlord_" .. e.key:lower() .. ".tga"] = crest_of[e.particle or ""] and icons[crest_of[e.particle]] or grey
    end
    for n = 1, warlords.breakaway_slots do
        icons["dp_emblem_breakaway_" .. n .. ".tga"] = grey
    end
end

local lines = {"return {"}
for _, line in ipairs(crests) do
    lines[#lines + 1] = line
end
lines[#lines + 1] = "}"
outputs["Scripts\\Library\\eawx-plugins\\diplomacy\\DiplomacyCrests.lua"] = lib.lines(lines)
outputs.icons = icons
outputs.done = done
return outputs
