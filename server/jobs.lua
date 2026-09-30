Jobs = { active = {} }

local cooldown = {}
local bayUse = {}
local hot, hotAt = {}, 0
local runSeq = 0

local AVERAGE_KMH = 55

local function spotBays(spotId, key)
    bayUse[spotId] = bayUse[spotId] or {}
    bayUse[spotId][key] = bayUse[spotId][key] or {}
    return bayUse[spotId][key]
end

local function pointFree(point)
    local here = vector3(point.x, point.y, point.z)
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh) and #(GetEntityCoords(veh) - here) < Config.Job.bayClearRadius then return false end
    end
    return true
end

local function pickBay(spotId, key, list)
    local used = spotBays(spotId, key)
    local best, bestAt
    for i, point in ipairs(list) do
        if pointFree(point) and (not bestAt or (used[i] or 0) < bestAt) then
            best, bestAt = i, used[i] or 0
        end
    end
    if best then used[best] = GetGameTimer() end
    return best and list[best] or nil
end

local function spawn(model, kind, point)
    local veh = CreateVehicleServerSetter(joaat(model), kind, point.x, point.y, point.z + 0.4, point.h)
    local waited = 0
    while (not veh or veh == 0 or not DoesEntityExist(veh)) and waited < 5000 do
        Wait(50)
        waited = waited + 50
    end
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    pcall(SetEntityOrphanMode, veh, 2)
    return veh
end

local function remove(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
end

local function coords(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local c = GetEntityCoords(entity)
    return { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(entity) }
end

local function health(entity)
    if not entity or not DoesEntityExist(entity) then return 0 end
    return GetVehicleBodyHealth(entity) + GetVehicleEngineHealth(entity)
end

local function rotateHot()
    local cfg = Config.Pay.hot
    if not SGet('hot.enabled', cfg.enabled) then
        hot = {}
        return
    end

    local every = SGet('hot.rotateMinutes', cfg.rotateMinutes) * 60
    if next(hot) and os.time() - hotAt < every then return end

    hotAt = os.time()
    local pool = {}
    for _, route in pairs(Spots.routes) do
        if route.enabled and not route.illegal then pool[#pool + 1] = route.id end
    end
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    hot = {}
    for i = 1, math.min(SGet('hot.count', cfg.count), #pool) do hot[pool[i]] = true end
end

local function hotLeft()
    return math.max(0, SGet('hot.rotateMinutes', Config.Pay.hot.rotateMinutes) * 60 - (os.time() - hotAt))
end

local function certFor(route)
    if route.cert == false then return nil end
    if route.cert then return route.cert end
    local kind = Util.TrailerType(route.type)
    return kind and kind.cert or nil
end

local function lockReason(route, profile, cid)
    if profile.level < route.level then return ('Level %d'):format(route.level) end
    local cert = certFor(route)
    if cert and not Progress.HasCert(cid, cert) then
        local def = Util.Certificate(cert)
        return ('%s certificate'):format(def and def.label or cert)
    end
    if route.illegal then
        if not SGet('illegal.enabled', Config.Illegal.enabled) then return 'Turned off' end
        if profile.level < Config.Illegal.level then return ('Level %d'):format(Config.Illegal.level) end
        if profile.heat >= Config.Illegal.blockAt then return 'Too much heat' end
    end
    return nil
end

local function publicLoad(route, spot, profile, cid)
    local origin = Spots.Origin(spot, route)
    local km = Util.RouteLength(route, origin) / 1000
    local kind = Util.TrailerType(route.type)
    local cert = certFor(route)
    local certDef = cert and Util.Certificate(cert)

    local stops = {}
    for i, stop in ipairs(route.stops) do stops[i] = { x = stop.x, y = stop.y, z = stop.z } end

    return {
        id = route.id,
        label = route.label,
        cargo = route.cargo,
        type = route.type,
        typeLabel = kind and kind.label or route.type,
        weight = route.weight,
        km = Util.Round(km, 2),
        minutes = math.max(2, math.floor(km / AVERAGE_KMH * 60 + 2.5)),
        pay = route.pay,
        xp = route.xp,
        level = route.level,
        cert = cert,
        certLabel = certDef and certDef.label or nil,
        timer = route.timer,
        convoy = route.convoy,
        escorts = route.escorts,
        illegal = route.illegal,
        fragile = route.fragile,
        hot = hot[route.id] == true,
        stops = stops,
        origin = origin and { x = origin.x, y = origin.y, z = origin.z } or nil,
        remotePickup = route.pickup ~= nil,
        locked = lockReason(route, profile, cid),
    }
end

function Jobs.Board(src, spotId)
    local cid = Framework.GetCitizenId(src)
    local spot = Spots.Get(spotId)
    if not cid or not spot then return nil end

    rotateHot()
    local profile = Progress.Profile(src)
    local loads = {}

    for _, route in ipairs(Spots.RoutesAt(spot.id)) do
        if not route.illegal or SGet('illegal.enabled', Config.Illegal.enabled) then
            loads[#loads + 1] = publicLoad(route, spot, profile, cid)
        end
    end

    local truck = Garage.Selected(src, 'truck')
    local trailer = Garage.Selected(src, 'trailer')

    return {
        spot = { id = spot.id, name = spot.name, laptop = { x = spot.laptop.x, y = spot.laptop.y } },
        loads = loads,
        hotBonus = SGet('hot.bonus', Config.Pay.hot.bonus),
        hotLeft = hotLeft(),
        profile = profile,
        truck = truck and { id = truck.id, label = truck.nickname or truck.label, model = truck.model, condition = truck.condition,
            parts = Garage.Parts(truck), business = truck.company_id ~= nil, bonus = (Util.ShopTruck(truck.model) or {}).bonus or 0 } or nil,
        trailer = trailer and { id = trailer.id, label = trailer.nickname or trailer.label, type = trailer.trailer_type,
            bonus = (Util.ShopTrailer(trailer.model) or {}).bonus or 0 } or nil,
        run = Jobs.State(src),
        business = Business.Public(Business.ByCitizen(cid)),
    }
end

local function stateFor(job)
    if not job then return nil end
    local route = job.route
    local stops = {}
    for i, stop in ipairs(route.stops) do stops[i] = { x = stop.x, y = stop.y, z = stop.z, h = stop.h } end

    local target
    if job.stage == 'hookup' then
        target = job.trailerPoint
    elseif job.stage == 'enroute' then
        target = route.stops[job.stop]
    end

    return {
        id = job.id,
        stage = job.stage,
        spot = job.spot,
        spotName = job.spotName,
        routeId = route.id,
        label = route.label,
        cargo = route.cargo,
        type = route.type,
        typeLabel = (Util.TrailerType(route.type) or {}).label,
        weight = route.weight,
        pay = route.pay,
        xp = route.xp,
        illegal = route.illegal,
        fragile = route.fragile,
        hot = job.hot > 0,
        stops = stops,
        stop = job.stop,
        target = target and { x = target.x, y = target.y, z = target.z, h = target.h } or nil,
        returns = job.stage == 'return' and Spots.ReturnPoints(job.spot) or nil,
        startedAt = job.startedAt,
        deadline = job.deadline,
        now = os.time(),
        late = job.late,
        truckNet = job.truck.net,
        trailerNet = job.trailer and job.trailer.net or nil,
        truckLabel = job.truck.label,
        plate = job.truck.plate,
        tipped = job.tipped == true,
    }
end

function Jobs.State(src)
    return stateFor(Jobs.active[src])
end

local function push(job)
    TriggerClientEvent('XS-Trucking:client:run', job.src, stateFor(job))
end

function Jobs.SpotBusy(spotId)
    for _, job in pairs(Jobs.active) do
        if job.spot == spotId then return true end
    end
    return false
end

function Jobs.RouteBusy(routeId)
    for _, job in pairs(Jobs.active) do
        if job.route.id == routeId then return true end
    end
    return false
end

function Jobs.UsingOwned(ownedId)
    for _, job in pairs(Jobs.active) do
        if job.truck.owned == ownedId or (job.trailer and job.trailer.owned == ownedId) then return true end
    end
    return false
end

local function copyRoute(route)
    local out = {}
    for k, v in pairs(route) do out[k] = v end
    return out
end

function Jobs.Take(src, spotId, routeId, hour)
    if Jobs.active[src] then return false, 'You are already on a load.' end
    if cooldown[src] and cooldown[src] > os.time() then
        return false, ('Wait %d seconds before taking another load.'):format(cooldown[src] - os.time())
    end

    local cid = Framework.GetCitizenId(src)
    if not cid then return false, 'No character loaded.' end

    local spot = Spots.Get(spotId)
    if not spot or not spot.enabled then return false, 'This spot is closed.' end

    local ped = GetPlayerPed(src)
    local here = ped ~= 0 and GetEntityCoords(ped)
    if not here or #(here - vector3(spot.laptop.x, spot.laptop.y, spot.laptop.z)) > 15.0 then
        return false, 'You have to be at the laptop.'
    end

    local route = Spots.Route(routeId)
    if not route or not route.enabled or (route.spot ~= 0 and route.spot ~= spot.id) then
        return false, 'That load is not on this board.'
    end

    local profile = Progress.Profile(src)
    local locked = lockReason(route, profile, cid)
    if locked then return false, ('Locked: %s.'):format(locked) end

    local truckRow = Garage.Selected(src, 'truck')
    if truckRow and Jobs.UsingOwned(truckRow.id) then return false, 'Someone else is out in that truck.' end
    if truckRow and truckRow.condition <= 0 then return false, 'Your truck needs repairing first.' end

    local trailerRow = Garage.Selected(src, 'trailer')
    if trailerRow and (trailerRow.trailer_type ~= route.type or Jobs.UsingOwned(trailerRow.id)) then trailerRow = nil end

    local truckPoint = pickBay(spot.id, 'truck', spot.truckBays)
    if not truckPoint then return false, 'Every truck bay is blocked. Clear one and try again.' end

    local trailerPoint = route.pickup
    if not trailerPoint then
        trailerPoint = pickBay(spot.id, 'trailer', spot.trailerBays)
        if not trailerPoint then return false, 'Every trailer bay is blocked. Clear one and try again.' end
    elseif not pointFree(trailerPoint) then
        return false, 'Something is parked on the pickup point.'
    end

    local truckModel = truckRow and truckRow.model or spot.truckModel or Config.Trucks.depot.model
    local kind = Util.TrailerType(route.type)
    local trailerModel = trailerRow and trailerRow.model or route.model or kind.models[math.random(#kind.models)]

    local truck = spawn(truckModel, 'automobile', truckPoint)
    if not truck then return false, ('The truck (%s) could not be spawned. Check the model name.'):format(truckModel) end

    local trailer = spawn(trailerModel, 'trailer', trailerPoint)
    if not trailer then
        remove(truck)
        return false, ('The trailer (%s) could not be spawned. Check the model name.'):format(trailerModel)
    end

    local plate = truckRow and Garage.Plate(truckRow) or (Config.Job.platePrefix .. tostring(math.random(1000, 9999))):sub(1, 8)
    SetVehicleNumberPlateText(truck, plate)

    runSeq = runSeq + 1
    local bizRow = truckRow and truckRow.company_id or nil
    local shop = truckRow and Util.ShopTruck(truckRow.model)
    local trailerShop = trailerRow and Util.ShopTrailer(trailerRow.model)

    local job = {
        id = runSeq,
        src = src,
        cid = cid,
        name = Framework.GetName(src),
        spot = spot.id,
        spotName = spot.name,
        route = copyRoute(route),
        stage = 'hookup',
        stop = 1,
        startedAt = os.time(),
        night = hour and (hour >= 21 or hour < 5) or false,
        hot = hot[route.id] and SGet('hot.bonus', Config.Pay.hot.bonus) or 0,
        rating = profile.rating,
        truckPoint = truckPoint,
        trailerPoint = trailerPoint,
        truck = {
            entity = truck, net = NetworkGetNetworkIdFromEntity(truck), model = truckModel, plate = plate,
            label = truckRow and (truckRow.nickname or truckRow.label) or Config.Trucks.depot.label,
            owned = truckRow and truckRow.id or nil, bonus = shop and shop.bonus or 0, business = bizRow,
        },
        trailer = {
            entity = trailer, net = NetworkGetNetworkIdFromEntity(trailer), model = trailerModel,
            owned = trailerRow and trailerRow.id or nil, bonus = trailerShop and trailerShop.bonus or 0,
        },
    }

    if route.timer and route.timer > 0 then
        local extra = Progress.Mod(cid, 'timer') / 100
        job.deadline = os.time() + math.floor(route.timer * (1 + extra))
    end

    Entity(truck).state:set('xsTrucking', { run = job.id, driver = src }, true)
    Entity(trailer).state:set('xsTrucking', { run = job.id, driver = src, illegal = route.illegal }, true)

    Jobs.active[src] = job
    job.baseline = health(truck)
    Keys.Give(src, truck, plate)

    local props = { plate = plate }
    if truckRow then
        props.upgrades = Util.Decode(truckRow.upgrades) or {}
        props.livery = Util.Decode(truckRow.livery) or {}
        local parts = Garage.Parts(truckRow)
        props.fuel = parts.fuel
        props.parts = parts
    else
        props.fuel = 100
    end

    TriggerClientEvent('XS-Trucking:client:runStarted', src, stateFor(job), props)
    return true, stateFor(job)
end

local function tipOff(job)
    if job.tipped then return end
    job.tipped = true

    local where = coords(job.truck.entity) or coords(job.trailer.entity)
    if not where then return end

    local street = lib.callback.await('XS-Trucking:client:street', job.src, where) or ''
    local detail = ('Truck plate %s.'):format(job.truck.plate)
    Dispatch.Alert(where, street, detail)
    Framework.Notify(job.src, 'Someone reported your cargo. Expect the police.', 'error')
    push(job)
end

local function rollTip(job, stats)
    local cfg = Config.Illegal
    local chance = SGet('illegal.tipChance', cfg.tipChance) + Progress.Heat(stats) * cfg.heatChance
    chance = chance * (1 - math.min(Progress.Mod(job.cid, 'tipoff'), 90) / 100)
    chance = math.min(chance, cfg.maxChance)
    if math.random() * 100 >= chance then return end

    SetTimeout(math.random(20, 90) * 1000, function()
        if Jobs.active[job.src] == job and job.stage ~= 'return' then tipOff(job) end
    end)
end

function Jobs.Hooked(src)
    local job = Jobs.active[src]
    if not job or job.stage ~= 'hookup' then return false, 'Nothing to hitch.' end

    local truck, trailer = coords(job.truck.entity), coords(job.trailer.entity)
    if not truck or not trailer then return false, 'The truck or trailer is gone.' end
    if Util.Distance(truck, trailer) > 20.0 then return false, 'The trailer is not hitched.' end

    job.stage = 'enroute'
    job.hookedAt = os.time()

    if job.route.illegal then rollTip(job, Progress.Stats(job.cid)) end
    push(job)
    return true
end

local function dockScore(job, stop)
    local where = coords(job.trailer.entity)
    if not where then return 0 end
    local cfg = Config.Pay.dock
    local dist = Util.Distance2D(where, stop)
    local angle = Util.AngleDiff(where.h, stop.h)
    if dist > cfg.maxDistance or angle > cfg.maxAngle then return 0 end
    return (1 - dist / cfg.maxDistance) * 0.5 + (1 - angle / cfg.maxAngle) * 0.5
end

function Jobs.Deliver(src)
    local job = Jobs.active[src]
    if not job or job.stage ~= 'enroute' then return false, 'Nothing to deliver.' end

    local stop = job.route.stops[job.stop]
    local trailer = coords(job.trailer.entity)
    local truck = coords(job.truck.entity)
    if not trailer or not truck then return false, 'The truck or trailer is gone.' end
    if not Util.Near(trailer, stop, Config.Job.deliverRadius) then return false, 'Bring the trailer into the drop zone.' end
    if Util.Distance(truck, trailer) > 20.0 then return false, 'The truck has to be with the trailer.' end

    local ped = GetPlayerPed(src)
    if not Util.Near(coords(ped) or trailer, stop, Config.Job.deliverRadius + 15.0) then return false, 'You have to be with the load.' end

    if job.stop < #job.route.stops then
        job.stop = job.stop + 1
        push(job)
        return true, { final = false, stop = job.stop, stops = #job.route.stops }
    end

    job.dock = dockScore(job, stop)
    job.late = job.deadline and os.time() > job.deadline or false
    job.deliveredAt = os.time()
    remove(job.trailer.entity)
    job.trailer.gone = true
    job.stage = 'return'
    push(job)
    return true, { final = true, dock = job.dock, late = job.late }
end

local function payout(job, damage, km)
    local route = job.route
    local cid = job.cid
    local stats = Progress.Stats(cid)
    local score = math.max(0, math.min(100, 100 - math.floor(damage / Config.Pay.rating.damagePerPoint
        * (1 - math.min(Progress.Mod(cid, 'rating'), 90) / 100))))

    local rating = Progress.Rating(stats)
    local ctx = {
        km = km, weight = route.weight, night = job.night, type = route.type, illegal = route.illegal,
        business = job.truck.business ~= nil, rating = rating,
    }
    local mods = Progress.Mods(cid, ctx)
    local biz = Business.ByCitizen(cid)
    local bizMods = Business.Mods(biz)

    local parts = {
        hot = job.hot,
        truck = job.truck.bonus,
        trailer = job.trailer.owned and job.trailer.bonus or 0,
        multi = #route.stops > 1 and SGet('bonus.multiStop', Config.Pay.multiStopBonus) or 0,
        rating = 0,
        skills = math.floor(mods.pay or 0),
        dock = math.floor((mods.dock or 0) * (job.dock or 0)),
        business = job.truck.business and bizMods.pay or 0,
    }

    local r = Config.Pay.rating
    if rating >= r.bonusAt then
        parts.rating = SGet('bonus.ratingBonus', r.bonus)
    elseif rating <= r.penaltyAt then
        parts.rating = -SGet('bonus.ratingPenalty', r.penalty)
    end

    local pct = 0
    for _, value in pairs(parts) do pct = pct + value end

    local total = route.pay * (1 + pct / 100) * SGet('economy.payoutMult', 100) / 100
    if job.late then total = total * SGet('bonus.latePay', Config.Job.latePayPercent) / 100 end
    if route.fragile then total = total * (0.5 + score / 200) end
    total = math.max(0, math.floor(total))

    local xp = math.floor((route.xp or 0) * (1 + (mods.xp or 0) / 100) * SGet('economy.xpMult', 100) / 100)

    return {
        base = route.pay, total = total, xp = xp, score = score, parts = parts, pct = pct,
        late = job.late, dock = job.dock or 0, fragile = route.fragile, biz = biz, mods = mods,
    }
end

local function finish(job, fuel)
    Jobs.active[job.src] = nil

    local damage = math.max(0, (job.baseline or 0) - health(job.truck.entity))
    local km = Util.RouteLength(job.route, job.trailerPoint) / 1000
    local result = payout(job, damage, km)
    local route = job.route
    local cid, src = job.cid, job.src

    local driverPay, bizPay = result.total, 0
    local biz = result.biz

    if job.truck.business and not route.illegal then
        local truckBiz = Business.Get(job.truck.business)
        if truckBiz then
            local cut = math.min(100, Business.CutFor(truckBiz, cid) + (result.mods.cut or 0))
            driverPay = math.floor(result.total * cut / 100)
            bizPay = result.total - driverPay
            Business.Credit(truckBiz.id, bizPay, 'load', ('%s by %s'):format(route.label, job.name))
            Business.CountDelivery(truckBiz.id, cid, bizPay)
        end
    elseif biz and not route.illegal then
        Business.CountDelivery(biz.id, cid, 0)
    end

    if biz and not route.illegal then
        local rep = Config.Business.repPerLoad * (1 + ((result.mods.rep or 0) + Business.Mods(biz).rep) / 100)
        Business.AddRep(biz.id, math.floor(rep))
    end

    local paidItem = false
    if route.illegal then
        local cfg = Config.Illegal.payout
        if cfg.item and Inventory.Add(src, cfg.item, driverPay) then
            paidItem = true
        else
            Framework.AddMoney(src, cfg.account or 'cash', driverPay, 'XS-Trucking:illegal')
        end
        Progress.AddHeat(cid, math.floor(SGet('illegal.heatPerRun', Config.Illegal.heatPerRun)
            * (1 - math.min(Progress.Mod(cid, 'heatGain'), 90) / 100)))
    else
        Framework.AddMoney(src, Config.Payout.account, driverPay, 'XS-Trucking:load')
    end

    local stats = Progress.Stats(cid, job.name)
    local newXp = stats.xp + result.xp
    local newLevel = Util.LevelForXp(newXp)
    MySQL.update.await([[
        UPDATE xs_trucking_stats SET xp = ?, level = ?, total_completed = total_completed + 1,
            total_earned = total_earned + ?, rating_sum = rating_sum + ?, name = ? WHERE citizenid = ?
    ]], { newXp, newLevel, driverPay, result.score, job.name, cid })

    if job.truck.owned then
        Garage.ApplyTrip(Garage.Row(job.truck.owned), km * 1.6, damage, cid, fuel)
    end

    MySQL.insert([[
        INSERT INTO xs_trucking_deliveries
            (citizenid, contract_id, label, cargo_type, base_payout, final_payout, driver_cut, company_cut, company_id,
             truck_bonus_pct, hot_bonus_pct, multistop_bonus_pct, rating_bonus_pct, skill_bonus_pct, coop_bonus_pct,
             spoiled, trip_rating, stop_count, xp, distance_m, duration_seconds, spot_id, route_id, role, illegal)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, 0), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        cid, tostring(route.id), route.label, route.type, result.base, result.total, driverPay, bizPay, job.truck.business or 0,
        result.parts.truck + result.parts.trailer, result.parts.hot, result.parts.multi, result.parts.rating,
        result.parts.skills + result.parts.dock, 0, result.late and 1 or 0, result.score, #route.stops, result.xp,
        math.floor(km * 1000), os.time() - job.startedAt, job.spot, route.id, 'driver', route.illegal and 1 or 0,
    })

    remove(job.truck.entity)
    if not job.trailer.gone then remove(job.trailer.entity) end

    local summary = {
        label = route.label, cargo = route.cargo, base = result.base, total = result.total, driver = driverPay,
        business = bizPay, xp = result.xp, score = result.score, parts = result.parts, late = result.late,
        fragile = result.fragile, dock = math.floor((result.dock or 0) * 100), illegal = route.illegal,
        item = paidItem and Config.Illegal.payout.item or nil,
        level = newLevel, leveled = newLevel > stats.level, title = Util.LevelTitle(newLevel),
        minutes = math.floor((os.time() - job.startedAt) / 60),
        km = Util.Round(km, 2),
    }
    TriggerClientEvent('XS-Trucking:client:runEnded', src, 'done', summary)
    return summary
end

function Jobs.Return(src, fuel)
    local job = Jobs.active[src]
    if not job or job.stage ~= 'return' then return false, 'Nothing to bring back.' end

    local truck = coords(job.truck.entity)
    if not truck then return false, 'The truck is gone.' end

    local parked = false
    for _, point in ipairs(Spots.ReturnPoints(job.spot)) do
        if Util.Near(truck, point, Config.Job.returnRadius) then parked = true break end
    end
    if not parked then return false, 'Park the truck in a return bay.' end

    return true, finish(job, tonumber(fuel))
end

local function drop(job, reason, message)
    Jobs.active[job.src] = nil
    remove(job.truck.entity)
    if not job.trailer.gone then remove(job.trailer.entity) end
    TriggerClientEvent('XS-Trucking:client:runEnded', job.src, reason, { message = message })
end

function Jobs.Cancel(src)
    local job = Jobs.active[src]
    if not job then return false, 'You are not on a load.' end

    local fee = SGet('economy.cancelFee', Config.Job.cancelFee)
    if fee > 0 then
        local paid = Framework.RemoveMoney(src, Config.Payout.account, fee, 'XS-Trucking:cancel')
            or Framework.RemoveMoney(src, 'cash', fee, 'XS-Trucking:cancel')
        if not paid then return false, ('Dropping a load costs %s.'):format(Util.Money(fee)) end
    end

    cooldown[src] = os.time() + (Config.Job.cancelCooldown or 0)
    drop(job, 'cancelled', fee > 0 and ('Load dropped. %s fee.'):format(Util.Money(fee)) or 'Load dropped.')
    return true
end

function Jobs.Clear(cid)
    for src, job in pairs(Jobs.active) do
        if job.cid == cid then
            drop(job, 'cleared', 'An admin cleared your load.')
            return true
        end
    end
    return false, 'They are not on a load.'
end

function Jobs.List()
    local out = {}
    for src, job in pairs(Jobs.active) do
        local where = coords(job.truck.entity)
        out[#out + 1] = {
            source = src, citizenid = job.cid, name = job.name, spot = job.spotName, route = job.route.label,
            routeId = job.route.id, stage = job.stage, stop = job.stop, stops = #job.route.stops, illegal = job.route.illegal,
            tipped = job.tipped == true, startedAt = job.startedAt, plate = job.truck.plate,
            coords = where and { x = where.x, y = where.y } or nil,
        }
    end
    table.sort(out, function(a, b) return a.startedAt < b.startedAt end)
    return out
end

CreateThread(function()
    while true do
        Wait(5000)
        for _, job in pairs(Jobs.active) do
            if not DoesEntityExist(job.truck.entity) then
                drop(job, 'lost', 'Your truck is gone. The load was lost.')
            elseif not job.trailer.gone and not DoesEntityExist(job.trailer.entity) then
                drop(job, 'lost', 'The trailer is gone. The load was lost.')
            elseif GetVehicleEngineHealth(job.truck.entity) <= -3999.0 then
                drop(job, 'lost', 'Your truck was destroyed. The load was lost.')
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local job = Jobs.active[src]
    if job then
        Jobs.active[src] = nil
        remove(job.truck.entity)
        if not job.trailer.gone then remove(job.trailer.entity) end
    end
    cooldown[src] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, job in pairs(Jobs.active) do
        remove(job.truck.entity)
        if not job.trailer.gone then remove(job.trailer.entity) end
    end
end)
