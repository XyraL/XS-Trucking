-- ─────────────────────────────────────────────────────────────
-- Admin panel client relay
-- Opened via /Config.Trucking.AdminCommand, which server/admin.lua
-- permission-checks before this event ever fires. Nothing here decides who
-- is allowed in — it just opens the NUI when told to, and every callback
-- below is re-checked server-side anyway. A player who forges these NUI
-- messages reaches a guarded() handler and gets rejected.
-- ─────────────────────────────────────────────────────────────
RegisterNetEvent('XS-Trucking:client:openAdmin', function()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openAdmin' })
end)

RegisterNUICallback('closeAdmin', function(_, cb)
    SetNuiFocus(false, false)
    cb({})
end)

-- Thin proxies. Each one names its server counterpart directly so the
-- mapping stays greppable in both directions.
local RELAY = {
    adminOverview         = 'XS-Trucking:server:adminOverview',
    adminOnlineRoster     = 'XS-Trucking:server:adminOnlineRoster',
    adminListCompanies    = 'XS-Trucking:server:adminListCompanies',
    adminSettings         = 'XS-Trucking:server:adminSettings',
    adminRecentDeliveries = 'XS-Trucking:server:adminRecentDeliveries',
}

for nuiName, callbackName in pairs(RELAY) do
    RegisterNUICallback(nuiName, function(_, cb)
        cb(lib.callback.await(callbackName, false) or {})
    end)
end

RegisterNUICallback('adminSearchPlayers', function(data, cb)
    cb(lib.callback.await('XS-Trucking:server:adminSearchPlayers', false, data.query) or {})
end)

RegisterNUICallback('adminPlayerDetail', function(data, cb)
    cb(lib.callback.await('XS-Trucking:server:adminPlayerDetail', false, data.citizenid))
end)

RegisterNUICallback('adminListFleet', function(data, cb)
    cb(lib.callback.await('XS-Trucking:server:adminListFleet', false, data.filter) or {})
end)

-- Write actions all share the (ok, message) response shape.
local function action(nuiName, callbackName, argFn)
    RegisterNUICallback(nuiName, function(data, cb)
        local ok, message = lib.callback.await(callbackName, false, table.unpack(argFn(data)))
        cb({ ok = ok, message = message })
    end)
end

action('adminSetLevel',      'XS-Trucking:server:adminSetLevel',      function(d) return { d.citizenid, d.level } end)
action('adminAddXp',         'XS-Trucking:server:adminAddXp',         function(d) return { d.citizenid, d.amount } end)
action('adminResetRating',   'XS-Trucking:server:adminResetRating',   function(d) return { d.citizenid } end)
action('adminGiveCash',      'XS-Trucking:server:adminGiveCash',      function(d) return { d.citizenid, d.amount } end)
action('adminClearJob',      'XS-Trucking:server:adminClearJob',      function(d) return { d.citizenid } end)
action('adminRepairVehicle', 'XS-Trucking:server:adminRepairVehicle', function(d) return { d.ownedId } end)
action('adminClearDispatch', 'XS-Trucking:server:adminClearDispatch', function(d) return { d.ownedId } end)
action('adminDeleteVehicle', 'XS-Trucking:server:adminDeleteVehicle', function(d) return { d.ownedId } end)
action('adminSetTreasury',   'XS-Trucking:server:adminSetTreasury',   function(d) return { d.companyId, d.amount } end)
action('adminDisbandCompany','XS-Trucking:server:adminDisbandCompany',function(d) return { d.companyId } end)
action('adminSetSetting',    'XS-Trucking:server:adminSetSetting',    function(d) return { d.key, d.value } end)
action('adminResetSetting',  'XS-Trucking:server:adminResetSetting',  function(d) return { d.key } end)
