UI = { open = false, mode = nil, spot = nil }

local PLAYER = {
    board = true, take = true, cancel = true, run = true, profile = true, garage = true, selectVehicle = true,
    buyVehicle = true, sellVehicle = true, repair = true, service = true, refuel = true, upgrade = true, style = true,
    rename = true, reserve = true, sendRun = true, collectRun = true, runRoutes = true, skills = true, buySkill = true,
    respec = true, certs = true, earnCert = true, business = true, foundBusiness = true, businessInvite = true,
    businessLeave = true, businessKick = true, businessGrade = true, businessRanks = true, businessProfile = true,
    businessDeposit = true, businessWithdraw = true, businessPerk = true, businessSlots = true, businessTransfer = true,
    businessDisband = true, businessLedger = true, nearbyPlayers = true, leaderboards = true, history = true,
}

local ADMIN = {
    builder = true, saveSpot = true, deleteSpot = true, saveRoute = true, deleteRoute = true, suggestPay = true,
    adminOverview = true, adminRuns = true, adminPlayers = true, adminPlayer = true, adminPlayerAction = true,
    adminBusinesses = true, adminBusiness = true, adminBusinessAction = true, adminFleet = true,
    adminVehicleAction = true, adminSettings = true, adminSetSetting = true, adminResetSetting = true, adminLogs = true,
}

function UI.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function config()
    return {
        resource = GetCurrentResourceName(),
        currency = Config.Currency,
        unit = Config.DistanceUnit,
        maxLevel = Config.Levels.max,
        illegal = Config.Illegal.enabled,
        business = Config.Business.enabled,
    }
end

function UI.Show(mode, data)
    UI.open = true
    UI.mode = mode
    SetNuiFocus(true, true)
    data = data or {}
    data.config = config()
    UI.Send(mode, data)
end

function UI.Close()
    if not UI.open then return end
    UI.open = false
    UI.mode = nil
    SetNuiFocus(false, false)
    UI.Send('close')
end

function UI.OpenLaptop(spotId)
    if UI.open then return end
    local board = lib.callback.await('XS-Trucking:server:board', false, spotId)
    if not board then
        Framework.Notify('The trucking laptop is not available right now.', 'error')
        return
    end
    UI.spot = spotId
    UI.Show('laptop', { board = board, hour = GetClockHours() })
end

RegisterNUICallback('close', function(_, cb)
    UI.Close()
    cb(true)
end)

RegisterNUICallback('rpc', function(data, cb)
    local name = data and data.fn
    if type(name) ~= 'string' or not (PLAYER[name] or (ADMIN[name] and (UI.mode == 'builder' or UI.mode == 'admin'))) then
        cb({ ok = false, error = 'Not allowed.' })
        return
    end

    local args = type(data.args) == 'table' and data.args or {}
    if name == 'take' then args[3] = GetClockHours() end

    local results = { lib.callback.await('XS-Trucking:server:' .. name, false, table.unpack(args, 1, 6)) }
    cb({ ok = results[1] ~= false and results[1] ~= nil, result = results[1], extra = results[2] })
end)

RegisterNUICallback('waypoint', function(data, cb)
    if data and tonumber(data.x) and tonumber(data.y) then
        SetNewWaypoint(tonumber(data.x) + 0.0, tonumber(data.y) + 0.0)
    end
    cb(true)
end)

RegisterNetEvent('XS-Trucking:client:businessInvite', function(data)
    local answer = lib.alertDialog({
        header = 'Business invite',
        content = ('%s invited you to join %s.'):format(data.from or 'Someone', data.business or 'their business'),
        centered = true,
        cancel = true,
        labels = { confirm = 'Join', cancel = 'No thanks' },
    })
    if answer ~= 'confirm' then return end

    local ok, result = lib.callback.await('XS-Trucking:server:businessAccept', false)
    Framework.Notify(ok and ('You joined %s.'):format(result or 'the business') or (result or 'Could not join.'), ok and 'success' or 'error')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if UI.open then SetNuiFocus(false, false) end
end)
