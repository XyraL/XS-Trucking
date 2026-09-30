Paths = {}

local KVP = 'xs_trucking:route:'
local SLOT_BLIP = 1
local SLOT_DISCRETE = 2
local STEP = 30.0
local MAX_LENGTH = 60000.0
local END_SLACK = 500.0
local STOP_SLACK = 300.0
local NEAR_START = 400.0

local known = {}
local queue = {}
local running = false
local failures = 0
local multiWorks = nil

local function log(message, ...)
    print(('^3[XS-Trucking]^0 map route: ' .. message):format(...))
end

local function hash(text)
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
    return ('%08x'):format(h)
end

local function encode(path)
    local parts = {}
    for i, p in ipairs(path) do parts[i] = ('%d,%d'):format(math.floor(p[1] + 0.5), math.floor(p[2] + 0.5)) end
    return table.concat(parts, ';')
end

local function decode(text)
    if type(text) ~= 'string' or text == '' then return nil end
    local path = {}
    for x, y in text:gmatch('(-?%d+),(-?%d+)') do path[#path + 1] = { tonumber(x), tonumber(y) } end
    return #path > 1 and path or nil
end

local function gap(a, x, y)
    local dx, dy = a[1] - x, a[2] - y
    return math.sqrt(dx * dx + dy * dy)
end

local function length(path)
    local total = 0.0
    for i = 2, #path do total = total + gap(path[i], path[i - 1][1], path[i - 1][2]) end
    return total
end

local function simplify(points, tolerance)
    if #points < 3 then return points end
    local keep = { [1] = true, [#points] = true }
    local stack = { { 1, #points } }
    while #stack > 0 do
        local range = table.remove(stack)
        local a, b = range[1], range[2]
        local ax, ay, bx, by = points[a][1], points[a][2], points[b][1], points[b][2]
        local dx, dy = bx - ax, by - ay
        local span = math.sqrt(dx * dx + dy * dy)
        local worst, index = 0.0, nil
        for i = a + 1, b - 1 do
            local px, py = points[i][1], points[i][2]
            local d = span < 0.001 and gap(points[i], ax, ay) or math.abs(dy * px - dx * py + bx * ay - by * ax) / span
            if d > worst then worst, index = d, i end
        end
        if index and worst > tolerance then
            keep[index] = true
            stack[#stack + 1] = { a, index }
            stack[#stack + 1] = { index, b }
        end
    end
    local out = {}
    for i = 1, #points do
        if keep[i] then out[#out + 1] = points[i] end
    end
    return out
end

local function sample(fromPlayer, slot)
    local ready = false
    for _ = 1, 30 do
        Wait(50)
        if GetPosAlongGpsTypeRoute(fromPlayer, 30.0, slot) then
            ready = true
            break
        end
    end
    if not ready then return {}, false end

    local out, distance = {}, 0.0
    while distance <= MAX_LENGTH do
        local ok, pos = GetPosAlongGpsTypeRoute(fromPlayer, distance, slot)
        if ok and pos then
            local last = out[#out]
            if last and math.abs(pos.x - last[1]) < 0.5 and math.abs(pos.y - last[2]) < 0.5 then break end
            out[#out + 1] = { pos.x, pos.y }
            if #out % 250 == 0 then Wait(0) end
        elseif #out > 0 or distance > 300.0 then
            break
        end
        distance = distance + STEP
    end
    return out, true
end

local function fit(raw, points)
    if #raw < 2 then return nil, 'no points came back' end
    local origin, finish = points[1], points[#points]
    local startGap, endGap = gap(raw[1], origin.x, origin.y), gap(raw[#raw], finish.x, finish.y)
    if startGap > END_SLACK then return nil, ('it started %dm from the depot'):format(math.floor(startGap)) end
    if endGap > END_SLACK then return nil, ('it ended %dm from the drop'):format(math.floor(endGap)) end

    local from = 1
    for i = 2, #points - 1 do
        local stop, hit = points[i], nil
        for j = from, #raw do
            if gap(raw[j], stop.x, stop.y) <= STOP_SLACK then
                hit = j
                break
            end
        end
        if not hit then return nil, ('it missed drop %d'):format(i - 1) end
        from = hit
    end

    local path = { { origin.x, origin.y } }
    for _, p in ipairs(raw) do path[#path + 1] = p end
    path[#path + 1] = { finish.x, finish.y }
    return simplify(path, 2.5)
end

local function viaMulti(points)
    ClearGpsMultiRoute()
    StartGpsMultiRoute(12, false, true)
    for _, p in ipairs(points) do AddPointToGpsMultiRoute(p.x + 0.0, p.y + 0.0, (p.z or 30.0) + 0.0) end
    SetGpsMultiRouteRender(true)

    local path, why
    for _, fromPlayer in ipairs({ false, true }) do
        local raw, ready = sample(fromPlayer, SLOT_DISCRETE)
        path, why = fit(raw, points)
        if path then break end
        why = ready and why or 'the GPS never answered'
    end
    ClearGpsMultiRoute()
    return path, why
end

local function viaBlip(points)
    if Run and Run.state then return nil, 'you are on a load' end

    local origin, first = points[1], points[2]
    local here = GetEntityCoords(cache.ped)
    if #(here - vector3(origin.x, origin.y, origin.z or here.z)) > NEAR_START then
        return nil, 'you are not at the start of it'
    end

    local blip = AddBlipForCoord(first.x + 0.0, first.y + 0.0, (first.z or 30.0) + 0.0)
    SetBlipAlpha(blip, 0)
    SetBlipRoute(blip, true)
    local raw, ready = sample(true, SLOT_BLIP)
    SetBlipRoute(blip, false)
    RemoveBlip(blip)

    local leg, why = fit(raw, { origin, first })
    if not leg then return nil, ready and why or 'the GPS never answered' end

    for i = 3, #points do leg[#leg + 1] = { points[i].x, points[i].y } end
    return leg, nil, #points > 2
end

local function compute(points, label)
    if multiWorks ~= false then
        local path, why = viaMulti(points)
        if path then
            multiWorks = true
            return path, false
        end
        if multiWorks == nil then
            multiWorks = false
            log('the multi-stop GPS gave nothing usable (%s), using a blip route instead', why)
        end
    end

    local path, why, partial = viaBlip(points)
    if not path then
        log('no road route for %s: %s', label, why)
        return nil
    end
    if Config.Debug then log('%s follows the roads (%d points%s)', label, #path, partial and ', first drop only' or '') end
    return path, partial
end

local function report(item, path)
    if not item.report or not item.route or not item.spot then return end
    lib.callback('XS-Trucking:server:roadLength', false, function() end, item.route, item.spot, math.floor(length(path)))
end

local function send(key, entry)
    UI.Send('path', { key = key, path = entry and entry.path or false, meters = entry and math.floor(length(entry.path)) or nil })
end

local function worker()
    running = true
    while #queue > 0 do
        if not UI.open then
            queue = {}
            break
        end

        local item = table.remove(queue, 1)
        local entry = known[item.key]
        if entry == nil and failures < 3 then
            local path, partial = compute(item.points, item.label)
            entry = path and { path = path, partial = partial } or false
            known[item.key] = entry
            if path then
                failures = 0
                if not partial then SetResourceKvp(KVP .. hash(item.key), encode(path)) end
            else
                failures = failures + 1
            end
        end

        send(item.key, entry)
        if entry and not entry.partial then report(item, entry.path) end
    end
    running = false
end

local function clean(points)
    if type(points) ~= 'table' or #points < 2 or #points > 10 then return nil end
    local out = {}
    for i, p in ipairs(points) do
        local x, y, z = tonumber(type(p) == 'table' and p.x), tonumber(type(p) == 'table' and p.y), tonumber(type(p) == 'table' and p.z)
        if not x or not y then return nil end
        out[i] = { x = x, y = y, z = z }
    end
    return out
end

RegisterNUICallback('paths', function(data, cb)
    local found = {}
    local list = type(data) == 'table' and type(data.routes) == 'table' and data.routes or {}

    for _, item in ipairs(list) do
        local key = type(item) == 'table' and type(item.key) == 'string' and #item.key <= 400 and item.key or nil
        local points = key and clean(item.points)
        if points then
            local entry = known[key]
            if entry == nil then
                local saved = decode(GetResourceKvpString(KVP .. hash(key)))
                if saved then
                    entry = { path = saved, partial = false }
                    known[key] = entry
                end
            end

            if entry ~= nil then
                found[#found + 1] = { key = key, path = entry and entry.path or false, meters = entry and math.floor(length(entry.path)) or nil }
                if entry and not entry.partial then report(item, entry.path) end
            else
                queue[#queue + 1] = {
                    key = key, points = points, report = item.report == true, label = type(item.label) == 'string' and item.label:sub(1, 48) or 'a route',
                    route = tonumber(item.route), spot = tonumber(item.spot),
                }
            end
        end
    end

    cb(found)
    if #queue > 0 and not running then CreateThread(worker) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and running then ClearGpsMultiRoute() end
end)
