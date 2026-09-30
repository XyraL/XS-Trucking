Keys = { name = nil }

local SUPPORTED = {
    'qbx_vehiclekeys', 'Renewed-Vehiclekeys', 'wasabi_carlock', 'qs-vehiclekeys', 'mk_vehiclekeys',
    'cd_garage', 'okokGarage', 't1ger_keys', 'vehicles_keys', 'qb-vehiclekeys',
}

do
    local forced = Config.Bridges.keys
    if forced ~= 'auto' then
        Keys.name = forced ~= 'none' and forced or nil
    else
        for _, resource in ipairs(SUPPORTED) do
            if GetResourceState(resource) == 'started' then
                Keys.name = resource
                break
            end
        end
    end
end

local SERVER_SIDE = {
    qbx_vehiclekeys = true, ['Renewed-Vehiclekeys'] = true, wasabi_carlock = true, custom = true,
}

if IsDuplicityVersion() then
    function Keys.Give(src, vehicle, plate)
        if not Keys.name then return end

        if not SERVER_SIDE[Keys.name] then
            TriggerClientEvent('XS-Trucking:client:giveKeys', src, NetworkGetNetworkIdFromEntity(vehicle), plate)
            return
        end

        local ok, err = pcall(function()
            if Keys.name == 'qbx_vehiclekeys' then
                exports.qbx_vehiclekeys:GiveKeys(src, vehicle, true)
            elseif Keys.name == 'Renewed-Vehiclekeys' then
                exports['Renewed-Vehiclekeys']:addKey(src, plate)
            elseif Keys.name == 'wasabi_carlock' then
                exports.wasabi_carlock:GiveKey(src, plate)
            elseif Keys.name == 'custom' then
                if Config.CustomKeysEvent == '' then error('Config.CustomKeysEvent is empty') end
                TriggerEvent(Config.CustomKeysEvent, src, plate, NetworkGetNetworkIdFromEntity(vehicle))
            end
        end)

        if not ok then
            print(('^1[XS-Trucking]^0 keys through %s failed for %s: %s'):format(Keys.name, plate, tostring(err)))
        end
    end
else
    RegisterNetEvent('XS-Trucking:client:giveKeys', function(netId, plate)
        if not Keys.name then return end

        local vehicle = 0
        for _ = 1, 100 do
            if NetworkDoesNetworkIdExist(netId) then
                vehicle = NetworkGetEntityFromNetworkId(netId)
                if vehicle ~= 0 and DoesEntityExist(vehicle) then break end
                vehicle = 0
            end
            Wait(50)
        end

        local ok, err = pcall(function()
            if Keys.name == 'qb-vehiclekeys' then
                TriggerEvent('vehiclekeys:client:SetOwner', plate)
            elseif Keys.name == 'qs-vehiclekeys' then
                local model = vehicle ~= 0 and GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) or nil
                exports['qs-vehiclekeys']:GiveKeys(plate, model)
            elseif Keys.name == 'mk_vehiclekeys' then
                if vehicle ~= 0 then exports['mk_vehiclekeys']:AddKey(vehicle) end
            elseif Keys.name == 'cd_garage' then
                TriggerEvent('cd_garage:AddKeys', plate)
            elseif Keys.name == 'okokGarage' then
                TriggerServerEvent('okokGarage:GiveKeys', plate)
            elseif Keys.name == 't1ger_keys' then
                TriggerServerEvent('t1ger_keys:updateOwnedKeys', plate, true)
            elseif Keys.name == 'vehicles_keys' then
                TriggerServerEvent('vehicles_keys:selfGiveVehicleKeys', plate)
            end
        end)

        if not ok then
            print(('^1[XS-Trucking]^0 keys through %s failed for %s: %s'):format(Keys.name, plate, tostring(err)))
        end
    end)
end
