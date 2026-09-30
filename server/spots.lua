Spots = { spots = {}, routes = {} }

local MAX_BAYS = 12
local MAX_STOPS = 8
local MODEL_PATTERN = '^[%w_%-]+$'

local function modelName(value)
    if type(value) ~= 'string' then return nil end
    value = Util.Trim(value):lower()
    if value == '' or #value > 32 or not value:match(MODEL_PATTERN) then return nil end
    return value
end

local function normalizeSpot(draft)
    if type(draft) ~= 'table' then return nil, 'Nothing to save.' end

    local name = Util.Text(draft.name, 48)
    if #name < 2 then return nil, 'Give the spot a name.' end

    local laptop = Util.Point(draft.laptop)
    if not laptop then return nil, 'Place the laptop.' end

    local truckBays = Util.Points(draft.truckBays, MAX_BAYS)
    if #truckBays == 0 then return nil, 'Place at least one truck bay.' end

    local trailerBays = Util.Points(draft.trailerBays, MAX_BAYS)
    if #trailerBays == 0 then return nil, 'Place at least one trailer bay.' end

    local blip = type(draft.blip) == 'table' and draft.blip or {}
    local prop = draft.laptop and draft.laptop.prop
    laptop.prop = prop ~= false and modelName(prop) or false

    return {
        name = name,
        enabled = draft.enabled ~= false,
        blip = {
            show = blip.show ~= false,
            sprite = math.floor(Util.Clamp(blip.sprite or 477, 1, 900)),
            colour = math.floor(Util.Clamp(blip.colour or 5, 0, 85)),
            scale = Util.Round(Util.Clamp(blip.scale or 0.8, 0.4, 1.6), 2),
        },
        laptop = laptop,
        truckBays = truckBays,
        trailerBays = trailerBays,
        returns = Util.Points(draft.returns, MAX_BAYS),
        truckModel = modelName(draft.truckModel),
    }
end

local function normalizeRoute(draft)
    if type(draft) ~= 'table' then return nil, 'Nothing to save.' end

    local label = Util.Text(draft.label, 48)
    if #label < 2 then return nil, 'Give the route a name.' end

    local kind = Util.TrailerType(draft.type)
    if not kind then return nil, 'Pick a trailer type.' end

    local stops = Util.Points(draft.stops, MAX_STOPS)
    if #stops == 0 then return nil, 'Place at least one drop point.' end

    local spot = math.floor(tonumber(draft.spot) or 0)
    if spot ~= 0 and not Spots.spots[spot] then return nil, 'That trucking spot is gone.' end

    local cert = draft.cert
    if cert == nil or cert == '' then
        cert = nil
    elseif cert ~= false and not Util.Certificate(cert) then
        return nil, 'That certificate does not exist.'
    end

    local convoy
    if type(draft.convoy) == 'table' and Config.Coop.convoy.enabled then
        local max = math.floor(Util.Clamp(draft.convoy.max, 2, Config.Coop.convoy.maxTrucks))
        convoy = { min = math.floor(Util.Clamp(draft.convoy.min, 1, max)), max = max }
    end

    local guards
    local cfg = Config.Guards
    if type(draft.guards) == 'table' and draft.illegal == true and cfg and cfg.enabled then
        if not Util.Point(draft.pickup) then return nil, 'Armed guards stand at the pickup point. Turn on the pickup and place it.' end
        local function option(list, id, fallback)
            return (Util.Find(list, id) or Util.Find(list, fallback) or list[1]).id
        end
        guards = {
            count = math.floor(Util.Clamp(draft.guards.count or 6, 1, cfg.maxGuards)),
            weapon = option(cfg.weapons, draft.guards.weapon, 'smg'),
            armour = option(cfg.armour, draft.guards.armour, 'light'),
            accuracy = option(cfg.accuracy, draft.guards.accuracy, 'medium'),
        }
        convoy = nil
    end

    return {
        spot = spot,
        label = label,
        cargo = Util.Text(draft.cargo, 48),
        type = kind.id,
        model = modelName(draft.model),
        weight = math.floor(Util.Clamp(draft.weight or 10, 0, 200)),
        pickup = Util.Point(draft.pickup),
        stops = stops,
        pay = math.floor(Util.Clamp(draft.pay, 0, 10000000)),
        xp = math.floor(Util.Clamp(draft.xp, 0, 100000)),
        level = math.floor(Util.Clamp(draft.level or 1, 1, Config.Levels.max)),
        cert = cert,
        timer = math.floor(Util.Clamp(draft.timer or 0, 0, 7200)),
        convoy = convoy,
        escorts = Config.Coop.escort.enabled and math.floor(Util.Clamp(draft.escorts or 0, 0, 3)) or 0,
        illegal = draft.illegal == true,
        fragile = draft.fragile == true,
        guards = guards,
        enabled = draft.enabled ~= false,
    }
end

Spots.NormalizeRoute = normalizeRoute

local function spotRow(row)
    local data = Util.Decode(row.data) or {}
    data.name = row.name
    data.enabled = Util.Truthy(row.enabled)
    local spot = normalizeSpot(data)
    if not spot then return nil end
    spot.id = row.id
    spot.enabled = Util.Truthy(row.enabled)
    return spot
end

local function routeRow(row)
    local data = Util.Decode(row.data) or {}
    data.label = row.label
    data.spot = 0
    local route = normalizeRoute(data)
    if not route then return nil end
    route.id = row.id
    route.spot = tonumber(row.spot_id) or 0
    route.enabled = Util.Truthy(row.enabled)
    return route
end

local function spotData(spot)
    return json.encode({
        blip = spot.blip, laptop = spot.laptop, truckBays = spot.truckBays, trailerBays = spot.trailerBays,
        returns = spot.returns, truckModel = spot.truckModel,
    })
end

local function routeData(route)
    return json.encode({
        cargo = route.cargo, type = route.type, model = route.model, weight = route.weight, pickup = route.pickup,
        stops = route.stops, pay = route.pay, xp = route.xp, level = route.level, cert = route.cert,
        timer = route.timer, convoy = route.convoy, escorts = route.escorts, illegal = route.illegal, fragile = route.fragile,
        guards = route.guards,
    })
end

local function seed()
    local spot = normalizeSpot(Config.DefaultSpot)
    if not spot then
        print('^1[XS-Trucking]^0 Config.DefaultSpot is not valid, no default spot was made.')
        return
    end

    local id = MySQL.insert.await('INSERT INTO xs_trucking_spots (`name`, `data`, `enabled`, `created_by`) VALUES (?, ?, 1, ?)',
        { spot.name, spotData(spot), 'config' })

    local made = 0
    for _, entry in ipairs(Config.DefaultRoutes or {}) do
        local draft = {}
        for k, v in pairs(entry) do draft[k] = v end
        draft.spot = 0
        local route = normalizeRoute(draft)
        if route then
            MySQL.insert.await('INSERT INTO xs_trucking_routes (`spot_id`, `label`, `data`, `enabled`, `created_by`) VALUES (?, ?, ?, 1, ?)',
                { id, route.label, routeData(route), 'config' })
            made = made + 1
        end
    end

    print(('^2[XS-Trucking]^0 made the default spot %s with %d route(s).'):format(spot.name, made))
end

function Spots.Load()
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM xs_trucking_spots') or 0
    if tonumber(count) == 0 then seed() end

    Spots.spots, Spots.routes = {}, {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM xs_trucking_spots ORDER BY id') or {}) do
        local spot = spotRow(row)
        if spot then
            Spots.spots[spot.id] = spot
        else
            print(('^1[XS-Trucking]^0 trucking spot %s (#%d) is missing points and was skipped.'):format(row.name, row.id))
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM xs_trucking_routes ORDER BY id') or {}) do
        local route = routeRow(row)
        if route then Spots.routes[route.id] = route end
    end
end

function Spots.Get(id)
    return Spots.spots[tonumber(id) or -1]
end

function Spots.Route(id)
    return Spots.routes[tonumber(id) or -1]
end

function Spots.RoutesAt(spotId)
    local out = {}
    for _, route in pairs(Spots.routes) do
        if route.enabled and (route.spot == 0 or route.spot == spotId) then out[#out + 1] = route end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Spots.Origin(spot, route)
    if route and route.pickup then return route.pickup end
    return spot and spot.trailerBays[1] or nil
end

function Spots.ReturnPoints(spotId)
    local out = {}
    local function add(spot)
        local list = #spot.returns > 0 and spot.returns or spot.truckBays
        for _, point in ipairs(list) do out[#out + 1] = { spot = spot.id, x = point.x, y = point.y, z = point.z, h = point.h } end
    end

    if Config.Job.returnAnySpot then
        for _, spot in pairs(Spots.spots) do
            if spot.enabled then add(spot) end
        end
    elseif Spots.spots[spotId] then
        add(Spots.spots[spotId])
    end
    return out
end

function Spots.Public()
    local out = {}
    for _, spot in pairs(Spots.spots) do
        if spot.enabled then
            out[#out + 1] = { id = spot.id, name = spot.name, blip = spot.blip, laptop = spot.laptop }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Spots.Sync(target)
    TriggerClientEvent('XS-Trucking:client:spots', target or -1, Spots.Public())
end

function Spots.Builder()
    local spots, routes = {}, {}
    for _, spot in pairs(Spots.spots) do spots[#spots + 1] = spot end
    for _, route in pairs(Spots.routes) do routes[#routes + 1] = route end
    table.sort(spots, function(a, b) return a.id < b.id end)
    table.sort(routes, function(a, b) return a.id < b.id end)
    return { spots = spots, routes = routes }
end

function Spots.SaveSpot(src, draft)
    local spot, err = normalizeSpot(draft)
    if not spot then return false, err end

    local id = tonumber(draft.id)
    if id and Spots.spots[id] then
        MySQL.update.await('UPDATE xs_trucking_spots SET `name` = ?, `data` = ?, `enabled` = ? WHERE `id` = ?',
            { spot.name, spotData(spot), spot.enabled and 1 or 0, id })
    else
        id = MySQL.insert.await('INSERT INTO xs_trucking_spots (`name`, `data`, `enabled`, `created_by`) VALUES (?, ?, ?, ?)',
            { spot.name, spotData(spot), spot.enabled and 1 or 0, Framework.GetCitizenId(src) or '' })
    end

    spot.id = id
    Spots.spots[id] = spot
    Spots.Sync()
    return true, id
end

function Spots.DeleteSpot(id)
    id = tonumber(id)
    if not id or not Spots.spots[id] then return false, 'That spot is already gone.' end
    if Jobs and Jobs.SpotBusy(id) then return false, 'Someone is on a run from this spot right now.' end

    MySQL.update.await('DELETE FROM xs_trucking_routes WHERE `spot_id` = ?', { id })
    MySQL.update.await('DELETE FROM xs_trucking_spots WHERE `id` = ?', { id })

    Spots.spots[id] = nil
    for routeId, route in pairs(Spots.routes) do
        if route.spot == id then Spots.routes[routeId] = nil end
    end

    Spots.Sync()
    return true
end

function Spots.SaveRoute(src, draft)
    local route, err = normalizeRoute(draft)
    if not route then return false, err end

    local id = tonumber(draft.id)
    if id and Spots.routes[id] then
        MySQL.update.await('UPDATE xs_trucking_routes SET `spot_id` = ?, `label` = ?, `data` = ?, `enabled` = ? WHERE `id` = ?',
            { route.spot, route.label, routeData(route), route.enabled and 1 or 0, id })
    else
        id = MySQL.insert.await('INSERT INTO xs_trucking_routes (`spot_id`, `label`, `data`, `enabled`, `created_by`) VALUES (?, ?, ?, ?, ?)',
            { route.spot, route.label, routeData(route), route.enabled and 1 or 0, Framework.GetCitizenId(src) or '' })
    end

    route.id = id
    Spots.routes[id] = route
    return true, id
end

function Spots.DeleteRoute(id)
    id = tonumber(id)
    if not id or not Spots.routes[id] then return false, 'That route is already gone.' end
    if Jobs and Jobs.RouteBusy(id) then return false, 'Someone is hauling this route right now.' end

    MySQL.update.await('DELETE FROM xs_trucking_routes WHERE `id` = ?', { id })
    Spots.routes[id] = nil
    return true
end

function Spots.SuggestPay(route, origin)
    local cfg = Config.Pay.suggest
    local km = Util.RouteLength(route, origin) / 1000
    local mult = cfg.types[route.type] or 1.0
    local stops = math.max(0, #(route.stops or {}) - 1)
    local risk = route.guards and (1.4 + (tonumber(route.guards.count) or 6) * 0.06) or 1
    return {
        km = Util.Round(km, 2),
        pay = math.floor((cfg.base + km * cfg.perKm) * mult * risk * (1 + stops * 0.1) / 10 + 0.5) * 10,
        xp = math.floor((20 + km * cfg.xpPerKm) * mult),
    }
end
