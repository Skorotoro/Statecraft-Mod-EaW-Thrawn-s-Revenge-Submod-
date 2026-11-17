-- RepublicWorlds.lua: the peoples of each world, from Thrawn's population text (TEXT_PLANET_INFO_<PLANET>_POPULATION:
-- "Native: Bothan\nImmigrated: Human\n2.5 Billion"): world -> {natives = {...}, immigrants = {...}, population =
-- "2.5 Billion"}. Extinct peoples are left out; "Various" is kept (a world of many peoples).
local lib = gen.load("lib")

local DIR = "Scripts\\Library\\eawx-plugins\\new-republic\\"
local SKIP = {other = true, others = true, none = true, unknown = true}

local function quote(s)
    return string.format("%q", s)
end

local function peoples(line, label)
    local out = {}
    for part in (line:sub(#label + 1) .. "|"):gmatch("([^|]*)|") do
        local sp = lib.strip(part)
        if sp ~= "" and not sp:lower():find("extinct", 1, true) then
            sp = lib.strip((sp:gsub("%(.-%)", "")))
            if sp ~= "" and not SKIP[sp:lower()] then
                out[#out + 1] = sp
            end
        end
    end
    return out
end

local worlds = {}
for _, k in ipairs(gen.text_keys()) do
    local planet = k:match("^TEXT_PLANET_INFO_(.+)_POPULATION$")
    if planet and planet:upper():find("^[A-Z_][A-Z0-9_]*$") then
        local value = (gen.text(k) or ""):gsub("\\n", "\n")
        local entry = {natives = {}, immigrants = {}}
        for raw in (value .. "\n"):gmatch("([^\n]*)\n") do
            local line = lib.strip(raw)
            local low = line:lower()
            if low:sub(1, 7) == "native:" then
                entry.natives = peoples(line, "native:")
            elseif low:sub(1, 11) == "immigrated:" then
                entry.immigrants = peoples(line, "immigrated:")
            elseif line ~= "" and low ~= "none" and not low:find(":", 1, true) and line:find("%d") then
                entry.population = line
            end
        end
        if #entry.natives > 0 or #entry.immigrants > 0 or entry.population then
            worlds[planet:upper()] = entry
        end
    end
end

local lines = {"return {"}
for _, name in ipairs(lib.sorted_keys(worlds)) do
    local e = worlds[name]
    local function list(t)
        local q = {}
        for _, s in ipairs(t) do
            q[#q + 1] = quote(s)
        end
        return "{" .. table.concat(q, ", ") .. "}"
    end
    lines[#lines + 1] = string.format("    %s = {natives = %s, immigrants = %s%s},", name, list(e.natives),
        list(e.immigrants), e.population and (", population = " .. quote(e.population)) or "")
end
lines[#lines + 1] = "}"

local count = 0
for _ in pairs(worlds) do
    count = count + 1
end

return {
    [DIR .. "RepublicWorlds.lua"] = lib.latin1(lib.lines(lines)),
    count = count,
}
