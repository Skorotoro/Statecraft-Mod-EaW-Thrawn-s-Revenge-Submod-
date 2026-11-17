-- StealthUnits.lua: every unit type that stays hidden on the galaxy map (a Galactic_Stealth_Ability or a stealth company)
-- and the companies that carry one. Closed borders do not turn these back.
local lib = gen.load("lib")

local TAGS = {GroundCompany = true, SpaceUnit = true, UniqueUnit = true, Squadron = true, HeroCompany = true,
              GroundInfantry = true, GroundVehicle = true, HeroUnit = true, GenericHeroUnit = true, TransportUnit = true}

local stealth, companies = {}, {}
for _, path in ipairs(gen.list(0, "XML", "*.xml", "walk")) do
    lib.each_object(gen.read(0, path), function(_, name, body)
        local company = body:match("<Is_Stealth_Company>%s*([^<%s]+)")
        if body:find("<Galactic_Stealth_Ability", 1, true) or (company and company:lower():find("^y")) then
            stealth[name] = true
        end
        local units = body:match("<Company_Units>([^<]*)</Company_Units>")
        if units then
            companies[name] = units:upper()
        end
    end, TAGS)
end
for name, units in pairs(companies) do
    for member in units:gmatch("[%w_]+") do
        if stealth[member] then
            stealth[name] = true
        end
    end
end

local lines = {"return {"}
for _, name in ipairs(lib.sorted_keys(stealth)) do
    lines[#lines + 1] = string.format('    ["%s"] = true,', name)
end
lines[#lines + 1] = "}"

return {["Scripts\\Library\\eawx-plugins\\diplomacy\\StealthUnits.lua"] = lib.lines(lines), count = #lines - 2}
