RegisterNetEvent('XS-Trucking:client:builder', function()
    if UI.open then return end
    local data = lib.callback.await('XS-Trucking:server:builder', false)
    if not data then
        Framework.Notify('You cannot use the trucking builder.', 'error')
        return
    end
    local here = GetEntityCoords(cache.ped)
    data.player = { x = here.x, y = here.y, z = here.z, h = GetEntityHeading(cache.ped) }
    UI.Show('builder', data)
end)

RegisterNetEvent('XS-Trucking:client:admin', function()
    if UI.open then return end
    local data = lib.callback.await('XS-Trucking:server:adminOverview', false)
    if not data then
        Framework.Notify('You cannot use the trucking admin panel.', 'error')
        return
    end
    UI.Show('admin', { overview = data })
end)

RegisterNUICallback('openBuilder', function(_, cb)
    cb(true)
    UI.Close()
    Wait(150)
    ExecuteCommand(Config.Admin.builderCommand)
end)

RegisterNUICallback('place', function(data, cb)
    if UI.mode ~= 'builder' then
        cb(false)
        return
    end

    SetNuiFocus(false, false)
    UI.Send('hide')

    local point = Placement.Start({
        label = data.label,
        preview = data.preview,
        origin = data.origin,
        others = data.others,
    })

    SetNuiFocus(true, true)
    UI.Send('unhide')
    cb(point or false)
end)

RegisterNUICallback('here', function(_, cb)
    local here = GetEntityCoords(cache.ped)
    cb({ x = here.x, y = here.y, z = here.z, h = GetEntityHeading(cache.ped) })
end)

RegisterNUICallback('teleport', function(data, cb)
    if UI.mode ~= 'builder' and UI.mode ~= 'admin' then
        cb(false)
        return
    end
    local point = data and data.point
    if point and tonumber(point.x) then
        SetEntityCoords(cache.ped, point.x + 0.0, point.y + 0.0, (point.z or 0.0) + 0.5, false, false, false, false)
    end
    cb(true)
end)
