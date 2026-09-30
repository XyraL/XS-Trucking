CreateThread(function()
    if not DB.Install() then
        DB.failed = true
        print('^1[XS-Trucking]^0 The database could not be set up, so the job will not load.')
        return
    end

    Settings.Load()
    Spots.Load()
    DB.ready = true
    Spots.Sync()

    local spots, routes = 0, 0
    for _ in pairs(Spots.spots) do spots = spots + 1 end
    for _ in pairs(Spots.routes) do routes = routes + 1 end

    print(('[XS-Trucking] %d spot%s · %d route%s · framework %s · keys %s · dispatch %s'):format(
        spots, spots == 1 and '' or 's', routes, routes == 1 and '' or 's',
        Framework.name or 'none', Keys.name or 'none', Dispatch.name or 'notifications'))
end)

lib.callback.register('XS-Trucking:server:spots', function()
    if not WaitForDB() then return {} end
    return Spots.Public()
end)

RegisterCommand(Config.Admin.builderCommand, function(src)
    if src == 0 then return end
    if not Framework.IsAdmin(src) then
        Framework.Notify(src, 'You cannot use the trucking builder.', 'error')
        return
    end
    TriggerClientEvent('XS-Trucking:client:builder', src)
end, false)

RegisterCommand(Config.Admin.command, function(src)
    if src == 0 then return end
    if not Framework.IsAdmin(src) then
        Framework.Notify(src, 'You cannot use the trucking admin panel.', 'error')
        return
    end
    TriggerClientEvent('XS-Trucking:client:admin', src)
end, false)
