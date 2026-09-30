if not IsDuplicityVersion() and type(RegisterNUICallback) == 'function' then
    local _registerNUI = RegisterNUICallback

    RegisterNUICallback = function(name, handler)
        return _registerNUI(name, function(data, cb)
            CreateThread(function()
                handler(data, function(payload, ...)
                    if payload == nil then payload = false end
                    cb(payload, ...)
                end)
            end)
        end)
    end
end

Framework = { name = nil, core = nil }

local function detect()
    local forced = Config.Bridges.framework
    if forced == 'qbox' or forced == 'qbcore' then return forced end
    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    if GetResourceState('qb-core') == 'started' then return 'qbcore' end
    return nil
end

Framework.name = detect()

if Framework.name == 'qbcore' then
    Framework.core = exports['qb-core']:GetCoreObject()
elseif not Framework.name then
    print('^1[XS-Trucking]^0 No supported framework found. Start qbx_core or qb-core before XS-Trucking.')
end

local function fullName(data)
    local info = data and data.charinfo
    if not info then return nil end
    return (('%s %s'):format(info.firstname or '', info.lastname or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function isPoliceJob(job)
    if not job then return false end
    if job.type == 'leo' then return true end
    for _, name in ipairs(Config.Illegal.policeJobs or {}) do
        if job.name == name then return true end
    end
    return false
end

if IsDuplicityVersion() then
    function Framework.GetPlayer(src)
        if Framework.name == 'qbox' then return exports.qbx_core:GetPlayer(src) end
        if Framework.name == 'qbcore' then return Framework.core.Functions.GetPlayer(src) end
        return nil
    end

    function Framework.GetCitizenId(src)
        local player = Framework.GetPlayer(src)
        return player and player.PlayerData and player.PlayerData.citizenid or nil
    end

    function Framework.GetName(src)
        local player = Framework.GetPlayer(src)
        return fullName(player and player.PlayerData) or GetPlayerName(src) or 'Unknown'
    end

    function Framework.NameByCitizenId(citizenid)
        local src = Framework.SourceByCitizenId(citizenid)
        if src then return Framework.GetName(src) end

        local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
        local info = row and Util.Decode(row.charinfo)
        if info and info.firstname then return ('%s %s'):format(info.firstname, info.lastname or '') end
        return nil
    end

    function Framework.GetMoney(src, account)
        local player = Framework.GetPlayer(src)
        local money = player and player.PlayerData and player.PlayerData.money
        return math.floor(tonumber(money and money[account or 'cash']) or 0)
    end

    function Framework.AddMoney(src, account, amount, reason)
        local player = Framework.GetPlayer(src)
        if not player or amount <= 0 then return false end
        return player.Functions.AddMoney(account or 'bank', math.floor(amount), reason or 'XS-Trucking') ~= false
    end

    function Framework.RemoveMoney(src, account, amount, reason)
        local player = Framework.GetPlayer(src)
        if not player then return false end
        if amount <= 0 then return true end
        if Framework.GetMoney(src, account) < math.floor(amount) then return false end
        return player.Functions.RemoveMoney(account or 'bank', math.floor(amount), reason or 'XS-Trucking') ~= false
    end

    function Framework.Players()
        if Framework.name == 'qbox' then return exports.qbx_core:GetQBPlayers() or {} end
        if Framework.core then return Framework.core.Functions.GetQBPlayers() or {} end
        return {}
    end

    function Framework.SourceByCitizenId(citizenid)
        if not citizenid then return nil end
        for _, player in pairs(Framework.Players()) do
            local data = player.PlayerData
            if data and data.citizenid == citizenid then return data.source end
        end
        return nil
    end

    function Framework.IsPolice(src)
        local player = Framework.GetPlayer(src)
        local job = player and player.PlayerData and player.PlayerData.job
        return isPoliceJob(job) and (job.onduty ~= false)
    end

    function Framework.PoliceSources()
        local out = {}
        for _, player in pairs(Framework.Players()) do
            local data = player.PlayerData
            if data and isPoliceJob(data.job) and data.job.onduty ~= false then out[#out + 1] = data.source end
        end
        return out
    end

    function Framework.IsAdmin(src)
        local admin = Config.Admin

        if admin.acePermission and admin.acePermission ~= '' and IsPlayerAceAllowed(src, admin.acePermission) then
            return true
        end

        for _, group in ipairs(admin.groups or {}) do
            local ok, allowed = pcall(function()
                if Framework.name == 'qbox' then return exports.qbx_core:HasPermission(src, group) end
                return Framework.core and Framework.core.Functions.HasPermission(src, group)
            end)
            if ok and allowed then return true end
        end

        if #(admin.licenses or {}) > 0 then
            for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
                local license = identifier:match('^license2?:(.+)$')
                if license then
                    for _, allowed in ipairs(admin.licenses) do
                        if license == allowed then return true end
                    end
                end
            end
        end

        return false
    end

    function Framework.Notify(src, message, kind)
        if Config.Notify.style == 'framework' then
            if Framework.name == 'qbox' then
                exports.qbx_core:Notify(src, message, kind or 'inform')
            elseif Framework.core then
                TriggerClientEvent('QBCore:Notify', src, message, kind == 'error' and 'error' or 'success')
            end
            return
        end

        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Trucking',
            description = message,
            type = kind or 'inform',
            position = Config.Notify.position,
        })
    end
else
    function Framework.GetPlayerData()
        if Framework.name == 'qbox' then return exports.qbx_core:GetPlayerData() end
        if Framework.name == 'qbcore' then return Framework.core.Functions.GetPlayerData() end
        return nil
    end

    function Framework.GetCitizenId()
        local data = Framework.GetPlayerData()
        return data and data.citizenid or nil
    end

    function Framework.IsPolice()
        local data = Framework.GetPlayerData()
        local job = data and data.job
        return isPoliceJob(job) and (job.onduty ~= false)
    end

    function Framework.Notify(message, kind)
        if Config.Notify.style == 'framework' then
            if Framework.name == 'qbox' then
                exports.qbx_core:Notify(message, kind or 'inform')
                return
            end
            TriggerEvent('QBCore:Notify', message, kind == 'error' and 'error' or 'success')
            return
        end

        lib.notify({
            title = 'Trucking',
            description = message,
            type = kind or 'inform',
            position = Config.Notify.position,
        })
    end
end
