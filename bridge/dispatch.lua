Dispatch = { name = nil }

if not IsDuplicityVersion() then
    local blips = {}

    RegisterNetEvent('XS-Trucking:client:policeAlert', function(data)
        if not Framework.IsPolice() or type(data) ~= 'table' or not data.coords then return end

        Framework.Notify(('%s: %s. %s'):format(data.code or '10-66', data.title or 'Suspicious Cargo', data.street or ''), 'warning')

        local blip = AddBlipForCoord(data.coords.x + 0.0, data.coords.y + 0.0, data.coords.z + 0.0)
        SetBlipSprite(blip, data.sprite or 477)
        SetBlipColour(blip, data.colour or 1)
        SetBlipScale(blip, 1.0)
        SetBlipFlashes(blip, true)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(data.title or 'Suspicious Cargo')
        EndTextCommandSetBlipName(blip)
        blips[#blips + 1] = blip

        SetTimeout((data.seconds or 300) * 1000, function()
            if DoesBlipExist(blip) then RemoveBlip(blip) end
        end)
    end)

    AddEventHandler('onResourceStop', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        for _, blip in ipairs(blips) do
            if DoesBlipExist(blip) then RemoveBlip(blip) end
        end
    end)

    return
end

local CANDIDATES = {
    'XS-Dispatch', 'ps-dispatch', 'qs-dispatch', 'cd_dispatch', 'core_dispatch', 'rcore_dispatch', 'linden_outlawalert',
}

do
    local forced = Config.Bridges.dispatch
    if forced == 'none' then
        Dispatch.name = nil
    elseif forced ~= 'auto' then
        Dispatch.name = forced
    else
        for _, resource in ipairs(CANDIDATES) do
            if GetResourceState(resource) == 'started' then
                Dispatch.name = resource
                break
            end
        end
    end
end

local function jobs()
    return Config.Illegal.policeJobs or { 'police' }
end

local SENDERS = {}

SENDERS['XS-Dispatch'] = function(a)
    exports['XS-Dispatch']:CreateCall({
        type = 'custom', code = a.code, title = a.title, description = a.description,
        priority = 2, departments = { 'police' }, coords = a.coords, street = a.street,
        caller = 'Anonymous tip', anonymous = true, sprite = a.sprite, color = a.colour,
        origin = 'XS-Trucking',
    })
end

SENDERS['ps-dispatch'] = function(a)
    local list = { 'leo' }
    for _, job in ipairs(jobs()) do list[#list + 1] = job end

    exports['ps-dispatch']:SendTargetedAlert(Framework.PoliceSources(), {
        message = a.title, codeName = 'xs_trucking_cargo', code = a.code, icon = 'fas fa-truck',
        priority = 2, coords = a.coords, street = a.street, information = a.description,
        jobs = list, addToList = true,
        alert = {
            radius = 0, sprite = a.sprite, color = a.colour, scale = 1.0, length = math.ceil(a.seconds / 60),
            sound = 'Lose_1st', sound2 = 'GTAO_FM_Events_Soundset', offset = false, flash = true,
        },
    })
end

SENDERS['qs-dispatch'] = function(a)
    TriggerEvent('qs-dispatch:server:CreateDispatchCall', {
        job = jobs(), callLocation = a.coords, callCode = { code = a.code, snippet = a.title },
        message = a.description, flashes = true, image = nil,
        blip = { sprite = a.sprite, scale = 1.0, colour = a.colour, flashes = true, text = a.title, time = a.seconds * 1000 },
    })
end

SENDERS['cd_dispatch'] = function(a)
    TriggerClientEvent('cd_dispatch:AddNotification', -1, {
        job_table = jobs(), coords = a.coords, title = ('%s - %s'):format(a.code, a.title),
        message = a.description, flash = 0, unique_id = tostring(math.random(1000000, 9999999)), sound = 1,
        blip = { sprite = a.sprite, scale = 1.0, colour = a.colour, flashes = true, text = a.title,
                 time = math.ceil(a.seconds / 60), radius = 0 },
    })
end

SENDERS['core_dispatch'] = function(a)
    local ok = pcall(function()
        exports['core_dispatch']:sendAlert({
            code = a.code, message = a.title, extraInfo = { { icon = 'fa-truck', info = a.description } },
            coords = a.coords, priority = 1, job = jobs(), time = a.seconds * 1000, blip = a.sprite, color = a.colour,
        })
    end)
    if ok then return end

    for _, job in ipairs(jobs()) do
        TriggerEvent('core_dispatch:addCall', a.code, a.title, { { icon = 'fa-truck', info = a.description } },
            { a.coords.x, a.coords.y, a.coords.z }, job, a.seconds * 1000, a.sprite, a.colour, 1)
    end
end

SENDERS['rcore_dispatch'] = function(a)
    TriggerEvent('rcore_dispatch:server:sendAlert', {
        code = a.code, default_priority = 'medium', coords = a.coords, job = jobs(), text = a.description,
        type = 'alerts', blip_time = math.ceil(a.seconds / 60),
        blip = { sprite = a.sprite, colour = a.colour, scale = 1.0, text = a.title, flashes = true, radius = 0 },
    })
end

SENDERS['linden_outlawalert'] = function(a)
    TriggerEvent('wf-alerts:svNotify', {
        dispatchData = {
            displayCode = a.code, description = a.title, isImportant = 1, recipientList = jobs(),
            length = a.seconds * 1000, infoM = 'fa-truck', info = a.description,
            blipSprite = a.sprite, blipColour = a.colour, blipScale = 1.0,
        },
        caller = 'Anonymous tip',
        coords = a.coords,
    })
end

function Dispatch.Alert(coords, street, extra, preset)
    local cfg = preset or Config.Illegal.alert
    local alert = {
        code = cfg.code, title = cfg.title,
        description = extra and ('%s %s'):format(cfg.description, extra) or cfg.description,
        sprite = cfg.sprite, colour = cfg.colour, seconds = cfg.seconds or 300,
        coords = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0),
        street = street or '',
    }

    local send = Dispatch.name and SENDERS[Dispatch.name]
    if send and GetResourceState(Dispatch.name) == 'started' then
        local ok, err = pcall(send, alert)
        if ok then return true end
        print(('^1[XS-Trucking]^0 tip-off through %s failed: %s'):format(Dispatch.name, tostring(err)))
    end

    for _, src in ipairs(Framework.PoliceSources()) do
        TriggerClientEvent('XS-Trucking:client:policeAlert', src, {
            code = alert.code, title = alert.title, street = alert.street, sprite = alert.sprite,
            colour = alert.colour, seconds = alert.seconds,
            coords = { x = alert.coords.x, y = alert.coords.y, z = alert.coords.z },
        })
    end
    return true
end
