-- A globe icon for every planet surface texture (dp_globe_<texture>.tga, drawn from the planet's own
-- texture) and DiplomacyGlobes.lua: planet -> its globe icon (dp_globe_unknown.tga when there is none).
local lib = gen.load("lib")

local SKIP = {"cloud", "glow", "none", "ring", "atmos", "light", "fleet", "halo", "flare", "shield", "grid"}
local EXTENSIONS = {[".dds"] = true, [".tga"] = true, [".DDS"] = true, [".TGA"] = true}

-- the planet surface texture a galactic planet model names: its first BaseTexture that is not clouds,
-- glow, rings or an empty layer
local function surface_texture(model)
    local pos = 1
    while true do
        local s, e = model:find("BaseTexture\0\2", pos, true)
        if not s then
            return nil
        end
        local after = e + 1
        pos = after
        if model:sub(after, after) ~= "\n" then
            local run = model:match("^[%w_%-%.]+", after + 1)
            if run then
                -- the longest name ending in a texture extension (a regex's backtracking)
                for i = #run - 3, 2, -1 do
                    if EXTENSIONS[run:sub(i, i + 3)] then
                        local name = run:sub(1, i + 3)
                        local low = name:lower()
                        local skip = false
                        for _, word in ipairs(SKIP) do
                            if low:find(word, 1, true) then
                                skip = true
                                break
                            end
                        end
                        if not skip then
                            return name
                        end
                        pos = after + 1 + #name
                        break
                    end
                end
            end
        end
    end
end

local PI = math.pi
local SIZE, SPIN = 64, 0.35

-- The sphere is the same for every globe: per pixel, either a fixed pixel (outside: the halo or nothing) or
-- where it samples the texture (fractions of its width and height) and how it is lit.
local SPHERE = {}
do
    local r = SIZE / 2 - 1.5
    local lx, ly, lz = -0.55, 0.45, 0.7
    local ln = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / ln, ly / ln, lz / ln
    local blank = string.char(0, 0, 0, 0)
    for j = 0, SIZE - 1 do
        for i = 0, SIZE - 1 do
            local x = (i + 0.5 - SIZE / 2) / r
            local y = (SIZE / 2 - j - 0.5) / r
            local d2 = x * x + y * y
            local cell = blank
            if d2 > 1.0 then
                local dist = math.sqrt(d2)
                if dist < 1.06 then
                    cell = string.char(140, 190, 255, math.floor(90 * (1.06 - dist) / 0.06))
                end
            else
                local z = math.sqrt(1 - d2)
                local lat, lon = lib.asin(y), lib.atan2(x, z) + SPIN * 2 * PI
                local t = 1 - z
                local t2 = t * t
                local rim = t2 * t2
                local edge = math.max(0.0, math.min(1.0, (1 - math.sqrt(d2)) * r))
                cell = {(lon / (2 * PI)) % 1.0, 0.5 - lat / PI, 0.2 + 0.95 * math.max(0.0, x * lx + y * ly + z * lz),
                        90 * rim, 130 * rim, 200 * rim, math.floor(255 * edge)}
            end
            SPHERE[#SPHERE + 1] = cell
        end
    end
end

-- a lit globe (RGBA, transparent outside) from an equirectangular planet surface texture
local function globe(src)
    local w, h = gen.img_sampler_size(src)
    local pixel = gen.img_sample
    local out = {}
    local floor, min, char = math.floor, math.min, string.char
    for n, cell in ipairs(SPHERE) do
        if type(cell) == "string" then
            out[n] = cell
        else
            local sx = min(w - 1, floor(cell[1] * w))
            local sy = min(h - 1, floor(cell[2] * h))
            local cr, cg, cb = pixel(src, sx, sy)
            local k = cell[3]
            out[n] = char(min(255, floor(cr * k + cell[4])), min(255, floor(cg * k + cell[5])),
                          min(255, floor(cb * k + cell[6])), cell[7])
        end
    end
    return gen.img_frombytes("RGBA", SIZE, SIZE, table.concat(out))
end

local planet_models = {}
for _, path in ipairs(gen.list(0, "XML", "Planets*.xml", false)) do
    for raw, body in gen.read(0, path):gmatch('<Planet%s+Name="([^"]+)"(.-)</Planet>') do
        local model = body:match("<Galactic_Model_Name>%s*([^<%s]+)%s*</Galactic_Model_Name>")
        local name = raw:upper()
        if model and name:find("^[A-Z_][A-Z0-9_]*$") and not planet_models[name] then
            planet_models[name] = model
        end
    end
end

local files = lib.game_files()
local surfaces, models = {}, {}
for _, model in pairs(planet_models) do
    models[model:upper()] = model
end
for key, model in pairs(models) do
    local data = files:read(model)
    surfaces[key] = data and surface_texture(data) or false
end
local textures = {}
for _, t in pairs(surfaces) do
    if t and (not textures[t:upper()] or t < textures[t:upper()]) then
        textures[t:upper()] = t
    end
end
local icons, icon_of, missing = {}, {}, 0
for _, key in ipairs(lib.sorted_keys(textures)) do
    local texture = textures[key]
    local icon = "dp_globe_" .. texture:lower():gsub("%.[^%.]*$", ""):gsub("[^a-z0-9_]", "_") .. ".tga"
    local data = files:read(texture)
    local ok, image = pcall(gen.img_sampler, data or "")
    if data and ok then
        icons[icon] = globe(image)
        icon_of[key] = icon
    else
        missing = missing + 1
    end
end

local lines = {"return {"}
local count = 0
for _, planet in ipairs(lib.sorted_keys(planet_models)) do
    local texture = surfaces[planet_models[planet]:upper()]
    lines[#lines + 1] = string.format('    %s = "%s",', planet, texture and icon_of[texture:upper()] or "dp_globe_unknown.tga")
    count = count + 1
end
lines[#lines + 1] = "}"

local globes = 0
for _ in pairs(icons) do globes = globes + 1 end
return {["Scripts\\Library\\eawx-plugins\\diplomacy\\DiplomacyGlobes.lua"] = lib.lines(lines), icons = icons,
        count = {count, globes, missing}}
