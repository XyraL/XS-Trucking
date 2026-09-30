Run = { state = nil, truck = 0, trailer = 0, parts = nil }

local blip, busy, prompt = nil, false, nil
local returnBlips = {}

local function entityFromNet(netId, timeout)
    if not netId then return 0 end
    local waited = 0
    while waited < (timeout or 8000) do
        if NetworkDoesNetworkIdExist(netId) then
            local entity = NetworkGetEntityFromNetworkId(netId)
            if entity ~= 0 and DoesEntityExist(entity) then return entity end
        end
        Wait(50)
        waited = waited + 50
    end
    return 0
end

local function takeControl(entity)
    if entity == 0 then return false end
    local tries = 0
    while not NetworkHasControlOfEntity(entity) and tries < 60 do
        NetworkRequestControlOfEntity(entity)
        Wait(50)
        tries = tries + 1
    end
    return NetworkHasControlOfEntity(entity)
end

local function applyProps(vehicle, props)
    if vehicle == 0 or not props then return end
    SetVehicleModKit(vehicle, 0)

    for _, def in ipairs(Config.Upgrades.performance) do
        local level = tonumber(props.upgrades and props.upgrades[def.id]) or 0
        if level > 0 then
            if def.toggle then
                ToggleVehicleMod(vehicle, def.toggle, true)
            else
                SetVehicleMod(vehicle, def.mod, math.min(level, GetNumVehicleMods(vehicle, def.mod)) - 1, false)
            end
        end
    end

    local livery = props.livery or {}
    if livery.primary and livery.secondary then SetVehicleColours(vehicle, livery.primary, livery.secondary) end
    if livery.xenon ~= nil and livery.xenon ~= false then
        ToggleVehicleMod(vehicle, 22, true)
        SetVehicleXenonLightsColor(vehicle, livery.xenon)
    end
    if (livery.tint or 0) > 0 then SetVehicleWindowTint(vehicle, 4 - livery.tint) end
    if (livery.horn or -1) >= 0 then SetVehicleMod(vehicle, 14, livery.horn, false) end

    if props.plate then SetVehicleNumberPlateText(vehicle, props.plate) end
    SetVehicleNeedsToBeHotwired(vehicle, false)
    SetVehicleEngineOn(vehicle, false, true, true)
    if props.fuel then Fuel.Set(vehicle, props.fuel) end
end

local function warpInto(vehicle)
    local ped = cache.ped
    for _ = 1, 40 do
        if GetVehiclePedIsIn(ped, false) == vehicle then return true end
        SetPedIntoVehicle(ped, vehicle, -1)
        Wait(50)
    end
    return GetVehiclePedIsIn(ped, false) == vehicle
end

local function clearBlips()
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    blip = nil
    for _, b in ipairs(returnBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    returnBlips = {}
end

local function routeBlip(point, label, colour)
    clearBlips()
    if not point then return end
    blip = AddBlipForCoord(point.x, point.y, point.z)
    SetBlipSprite(blip, 477)
    SetBlipColour(blip, colour or 5)
    SetBlipScale(blip, 0.9)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, colour or 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
end

local function returnMarkers(points)
    clearBlips()
    local nearest, best = nil, math.huge
    local here = GetEntityCoords(cache.ped)
    for _, point in ipairs(points or {}) do
        local d = #(here - vector3(point.x, point.y, point.z))
        if d < best then nearest, best = point, d end
    end
    if nearest then routeBlip(nearest, 'Bring the truck back', 2) end
end

local function objective(state)
    if not state then return nil end
    if state.stage == 'hookup' then return 'Back the truck up to the trailer and hitch it' end
    if state.stage == 'enroute' then
        if #state.stops > 1 then return ('Deliver to drop %d of %d'):format(state.stop, #state.stops) end
        return 'Deliver the load'
    end
    return 'Bring the truck back to a trucking spot'
end

local function applyStage(state)
    Run.state = state
    if not state then
        clearBlips()
        return
    end

    if state.stage == 'hookup' then
        routeBlip(state.target, 'Your trailer', 5)
    elseif state.stage == 'enroute' then
        routeBlip(state.target, #state.stops > 1 and ('Drop %d of %d'):format(state.stop, #state.stops) or 'Drop point', state.illegal and 1 or 5)
    elseif state.stage == 'return' then
        Run.trailer = 0
        returnMarkers(state.returns)
    end
end

local function attached(truck)
    if truck == 0 or not DoesEntityExist(truck) then return false end
    return Citizen.InvokeNative(0xE7CF3C4F9F489F0C, truck) and true or false
end

local function hitchWatch(runId)
    CreateThread(function()
        local nextTry = 0
        while Run.state and Run.state.id == runId and Run.state.stage == 'hookup' do
            Wait(500)
            if attached(Run.truck) and GetGameTimer() >= nextTry then
                nextTry = GetGameTimer() + 4000
                local ok, err = lib.callback.await('XS-Trucking:server:hooked', false)
                if ok then
                    Framework.Notify('Trailer hitched. Head for the drop point.', 'success')
                elseif err then
                    Framework.Notify(err, 'error')
                end
            end
        end
    end)
end

local function drawZone(point, radius, r, g, b)
    DrawMarker(1, point.x, point.y, point.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        radius * 2.0, radius * 2.0, 1.2, r, g, b, 70, false, false, 2, false, nil, nil, false)
    if point.h then
        local h = math.rad(point.h)
        local dx, dy = -math.sin(h), math.cos(h)
        DrawMarker(21, point.x - dx * 4.0, point.y - dy * 4.0, point.z + 0.6, 0.0, 0.0, 0.0, 90.0, point.h + 90.0, 0.0,
            2.2, 2.2, 2.2, r, g, b, 160, false, false, 2, false, nil, nil, false)
    end
end

local function setPrompt(text)
    if prompt == text then return end
    prompt = text
    if text then lib.showTextUI(text, { position = 'left-center', icon = 'truck' }) else lib.hideTextUI() end
end

local function deliver()
    if busy then return end
    busy = true
    local ok, result = lib.callback.await('XS-Trucking:server:deliver', false)
    busy = false
    if not ok then
        Framework.Notify(result or 'You cannot drop it here.', 'error')
        return
    end
    if result and not result.final then
        Framework.Notify(('Drop done. %d to go.'):format(result.stops - result.stop + 1), 'success')
    else
        Framework.Notify(result and result.late and 'Delivered, but late. Take the truck back.' or 'Delivered. Take the truck back.', 'success')
    end
end

local function park()
    if busy then return end
    busy = true
    local fuel = Run.truck ~= 0 and Fuel.Get(Run.truck) or nil
    local ok, result = lib.callback.await('XS-Trucking:server:return', false, fuel)
    busy = false
    if not ok then Framework.Notify(result or 'Park it in a return bay.', 'error') end
end

CreateThread(function()
    while true do
        local state = Run.state
        if not state then
            setPrompt(nil)
            Wait(750)
        else
            Wait(0)
            local ped = cache.ped
            local here = GetEntityCoords(ped)

            if state.stage == 'enroute' and state.target then
                local t = state.target
                local dist = #(here - vector3(t.x, t.y, t.z))
                if dist < 120.0 then drawZone(t, Config.Job.deliverRadius, state.illegal and 255 or 56, state.illegal and 93 or 217, state.illegal and 108 or 255) end

                local inZone = Run.trailer ~= 0 and DoesEntityExist(Run.trailer)
                    and #(GetEntityCoords(Run.trailer) - vector3(t.x, t.y, t.z)) <= Config.Job.deliverRadius
                if inZone then
                    setPrompt('[E] Drop the load')
                    if IsControlJustReleased(0, 38) then deliver() end
                else
                    setPrompt(nil)
                end
            elseif state.stage == 'return' and state.returns then
                local near
                for _, point in ipairs(state.returns) do
                    local dist = #(here - vector3(point.x, point.y, point.z))
                    if dist < 90.0 then drawZone(point, Config.Job.returnRadius * 0.5, 63, 224, 143) end
                    if Run.truck ~= 0 and DoesEntityExist(Run.truck)
                        and #(GetEntityCoords(Run.truck) - vector3(point.x, point.y, point.z)) <= Config.Job.returnRadius then
                        near = point
                    end
                end
                if near then
                    setPrompt('[E] Hand the truck back')
                    if IsControlJustReleased(0, 38) then park() end
                else
                    setPrompt(nil)
                end
            elseif state.stage == 'hookup' and state.target then
                local t = state.target
                if #(here - vector3(t.x, t.y, t.z)) < 120.0 then drawZone(t, 3.0, 255, 181, 71) end
                setPrompt(nil)
            else
                setPrompt(nil)
            end
        end
    end
end)

local function penalties()
    local parts, truck = Run.parts, Run.truck
    if not parts or truck == 0 or not DoesEntityExist(truck) then return end
    local cfg = Config.Parts
    if not cfg.enabled then return end

    SetVehicleReduceGrip(truck, (parts.tyres or 100) < cfg.tyresGripBelow)

    if (parts.oil or 100) < cfg.oilEngineDrainBelow and GetEntitySpeed(truck) > 2.0 then
        SetVehicleEngineHealth(truck, math.max(200.0, GetVehicleEngineHealth(truck) - 0.2))
    end

end

CreateThread(function()
    local shown = false
    while true do
        Wait(250)
        local state = Run.state
        if state then
            local here = GetEntityCoords(cache.ped)
            local target = state.target
            if state.stage == 'return' and state.returns then
                local best
                for _, point in ipairs(state.returns) do
                    local d = #(here - vector3(point.x, point.y, point.z))
                    if not best or d < best then best, target = d, point end
                end
            end

            penalties()

            UI.Send('hud', {
                stage = state.stage,
                objective = objective(state),
                label = state.label,
                cargo = state.cargo,
                distance = target and #(here - vector3(target.x, target.y, target.z)) or nil,
                stop = state.stop,
                stops = #state.stops,
                deadline = state.deadline and (state.deadline - state.now) - math.floor((GetGameTimer() - (Run.stateAt or GetGameTimer())) / 1000) or nil,
                fuel = Run.truck ~= 0 and Fuel.Get(Run.truck) or nil,
                illegal = state.illegal,
                tipped = state.tipped,
                hitched = state.stage ~= 'hookup' or attached(Run.truck),
                speed = Run.truck ~= 0 and DoesEntityExist(Run.truck) and GetEntitySpeed(Run.truck) or 0,
            })
            shown = true
        elseif shown then
            UI.Send('hud', false)
            shown = false
        end
    end
end)

RegisterNetEvent('XS-Trucking:client:runStarted', function(state, props)
    Run.state = state
    Run.parts = props and props.parts or nil
    Run.stateAt = GetGameTimer()

    local truck = entityFromNet(state.truckNet)
    local trailer = entityFromNet(state.trailerNet)
    Run.truck, Run.trailer = truck, trailer

    if truck ~= 0 then
        if takeControl(truck) then
            applyProps(truck, props)
            if Run.parts and Config.Parts.enabled and (Run.parts.engine or 100) < Config.Parts.enginePowerBelow then
                ModifyVehicleTopSpeed(truck, -12.0)
            end
        end
        if Config.Job.warpIntoTruck then
            DoScreenFadeOut(250)
            Wait(300)
            warpInto(truck)
            DoScreenFadeIn(400)
        end
    end

    applyStage(state)
    hitchWatch(state.id)
    Framework.Notify(('%s: %s'):format(state.label, objective(state)), 'inform')
end)

RegisterNetEvent('XS-Trucking:client:run', function(state)
    if not state then return end
    Run.state = state
    Run.stateAt = GetGameTimer()
    if state.trailerNet and Run.trailer == 0 then Run.trailer = entityFromNet(state.trailerNet, 2000) end
    applyStage(state)
    if state.stage == 'hookup' then hitchWatch(state.id) end
end)

RegisterNetEvent('XS-Trucking:client:runEnded', function(reason, summary)
    Run.state = nil
    Run.truck, Run.trailer, Run.parts = 0, 0, nil
    clearBlips()
    setPrompt(nil)
    UI.Send('hud', false)

    if reason == 'done' then
        UI.Send('receipt', summary)
    elseif summary and summary.message then
        Framework.Notify(summary.message, reason == 'cancelled' and 'inform' or 'error')
    end
end)

CreateThread(function()
    while not Framework.GetCitizenId() do Wait(1000) end
    local state = lib.callback.await('XS-Trucking:server:run', false)
    if state then
        Run.state = state
        Run.stateAt = GetGameTimer()
        Run.truck = entityFromNet(state.truckNet, 3000)
        Run.trailer = entityFromNet(state.trailerNet, 3000)
        applyStage(state)
        if state.stage == 'hookup' then hitchWatch(state.id) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearBlips()
    if prompt then lib.hideTextUI() end
end)
