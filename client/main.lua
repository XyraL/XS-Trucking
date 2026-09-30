World = { spots = {} }

local blips = {}
local props = {}

local function clearWorld()
    for _, blip in pairs(blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    for _, prop in pairs(props) do
        if DoesEntityExist(prop) then DeleteEntity(prop) end
    end
    blips, props = {}, {}
    Target.Clear('xs_trucking_laptop')
end

local function addBlip(spot)
    if not spot.blip or spot.blip.show == false then return end
    local blip = AddBlipForCoord(spot.laptop.x, spot.laptop.y, spot.laptop.z)
    SetBlipSprite(blip, spot.blip.sprite or 477)
    SetBlipColour(blip, spot.blip.colour or 5)
    SetBlipScale(blip, (spot.blip.scale or 0.8) + 0.0)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(spot.name)
    EndTextCommandSetBlipName(blip)
    blips[spot.id] = blip
end

local function addProp(spot)
    local model = spot.laptop.prop
    if not model then return end

    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return end
    local p = spot.laptop
    if GetClosestObjectOfType(p.x, p.y, p.z, 1.0, hash, false, false, false) ~= 0 then return end

    if not pcall(lib.requestModel, hash, 5000) then return end
    local object = CreateObjectNoOffset(hash, p.x, p.y, p.z, false, false, false)
    SetEntityHeading(object, p.h or 0.0)
    FreezeEntityPosition(object, true)
    SetEntityInvincible(object, true)
    SetModelAsNoLongerNeeded(hash)
    props[spot.id] = object
end

local function addTarget(spot)
    Target.AddSphere(('xs_trucking_laptop:%d'):format(spot.id), spot.laptop, 1.2, {
        {
            id = 'open',
            label = 'Open trucking laptop',
            icon = 'fa-solid fa-truck-fast',
            distance = 2.5,
            action = function() UI.OpenLaptop(spot.id) end,
        },
    })
end

function World.Build(list)
    clearWorld()
    World.spots = {}
    for _, spot in ipairs(list or {}) do
        World.spots[spot.id] = spot
        addBlip(spot)
        addProp(spot)
        addTarget(spot)
    end
end

function World.Spot(id)
    return World.spots[id]
end

RegisterNetEvent('XS-Trucking:client:spots', function(list)
    World.Build(list)
end)

local function refresh()
    local list = lib.callback.await('XS-Trucking:server:spots', false)
    World.Build(list or {})
end

CreateThread(function()
    while not Framework.GetCitizenId() do Wait(1000) end
    refresh()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', refresh)
RegisterNetEvent('qbx_core:client:playerLoaded', refresh)

lib.callback.register('XS-Trucking:client:street', function(coords)
    if type(coords) ~= 'table' then return '' end
    local a, b = GetStreetNameAtCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    local street = GetStreetNameFromHashKey(a)
    local cross = b ~= 0 and GetStreetNameFromHashKey(b) or ''
    if cross ~= '' then return ('%s / %s'):format(street, cross) end
    return street or ''
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearWorld()
end)
