Fuel = { name = nil }

if IsDuplicityVersion() then return end

local EXPORTS = { LegacyFuel = true, ['cdn-fuel'] = true, ['ps-fuel'] = true, ['lj-fuel'] = true }

do
    local forced = Config.Bridges.fuel
    if forced ~= 'auto' then
        Fuel.name = forced ~= 'none' and forced or nil
    else
        for _, resource in ipairs({ 'ox_fuel', 'LegacyFuel', 'cdn-fuel', 'ps-fuel', 'lj-fuel' }) do
            if GetResourceState(resource) == 'started' then
                Fuel.name = resource
                break
            end
        end
    end
end

function Fuel.Set(vehicle, level)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    level = Util.Clamp(level, 0, 100) + 0.0

    SetVehicleFuelLevel(vehicle, level)
    if DecorIsRegisteredAsType('_Fuel_Level', 1) then DecorSetFloat(vehicle, '_Fuel_Level', level) end

    pcall(function()
        if Fuel.name == 'ox_fuel' then
            Entity(vehicle).state:set('fuel', level, true)
        elseif EXPORTS[Fuel.name] then
            exports[Fuel.name]:SetFuel(vehicle, level)
        end
    end)
end

function Fuel.Get(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return nil end

    local ok, level = pcall(function()
        if Fuel.name == 'ox_fuel' then return Entity(vehicle).state.fuel end
        if EXPORTS[Fuel.name] then return exports[Fuel.name]:GetFuel(vehicle) end
        return nil
    end)

    level = ok and tonumber(level) or nil
    if not level then level = GetVehicleFuelLevel(vehicle) end
    return Util.Clamp(level, 0, 100)
end
