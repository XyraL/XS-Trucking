Paths = {}

local KVP = 'xs_trucking:path:'
local SLOT_DISCRETE = 2
local STEP = 30.0
local MAX_LENGTH = 60000.0
local END_SLACK = 500.0
local STOP_SLACK = 300.0

local known = {}
local queue = {}
local running = false
local failures = 0

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

local function plot(points, fromPlayer)
    ClearGpsMultiRoute()
    StartGpsMultiRoute(12, fromPlayer, true)
    for _, p in ipairs(points) do AddPointToGpsMultiRoute(p.x + 0.0, p.y + 0.0, (p.z or 30.0) + 0.0) end
    SetGpsMultiRouteRender(true)
end

local function read(fromPlayer)
    local ready = false
    for _ = 1, 40 do
        Wait(50)
        if GetPosAlongGpsTypeRoute(fromPlayer, 0.0, SLOT_DISCRETE) then
            ready = true
            break
        end
    end
    if not ready then return {} end

    local out, distance = {}, 0.0
    while distance <= MAX_LENGTH do
        local ok, pos = GetPosAlongGpsTypeRoute(fromPlayer, distance, SLOT_DISCRETE)
        if not ok or not pos then break end
        local last = out[#out]
        if last and math.abs(pos.x - last[1]) < 0.5 and math.abs(pos.y - last[2]) < 0.5 then break end
        out[#out + 1] = { pos.x, pos.y }
        distance = distance + STEP
        if #out % 250 == 0 then Wait(0) end
    end
    return out
end

local function fit(raw, points, start)
    if #raw < 2 then return nil end
    local finish = points[#points]
    if gap(raw[1], start.x, start.y) > END_SLACK or gap(raw[#raw], finish.x, finish.y) > END_SLACK then return nil end

    local from = 1
    for i = 2, #points - 1 do
        local stop, hit = points[i], nil
        for j = from, #raw do
            if gap(raw[j], stop.x, stop.y) <= STOP_SLACK then hit = j break end
        end
        if not hit then return nil end
        from = hit
    end

    local path = { { start.x, start.y } }
    for _, p in ipairs(raw) do path[#path + 1] = p end
    path[#path + 1] = { finish.x, finish.y }
    return simplify(path, 2.5)
end

local function compute(points)
    plot(points, false)
    local path = fit(read(false), points, points[1]) or fit(read(true), points, points[1])

    local here = GetEntityCoords(cache.ped)
    local origin = points[1]
    if not path and #(here - vector3(origin.x, origin.y, origin.z or here.z)) < 400.0 then
        local rest = {}
        for i = 2, #points do rest[#rest + 1] = points[i] end
        plot(rest, true)
        path = fit(read(false), points, origin) or fit(read(true), points, origin)
    end

    ClearGpsMultiRoute()
    return path
end

local function report(item, path)
    if not item.report or not item.route or not item.spot then return end
    lib.callback('XS-Trucking:server:roadLength', false, function() end, item.route, item.spot, math.floor(length(path)))
end

local function send(key, path)
    UI.Send('path', { key = key, path = path or false, meters = path and math.floor(length(path)) or nil })
end

local function worker()
    running = true
    while #queue > 0 do
        if not UI.open then
            queue = {}
            break
        end

        local item = table.remove(queue, 1)
        local path = known[item.key]
        if path == nil and failures < 2 then
            path = compute(item.points) or false
            known[item.key] = path
            if path then
                failures = 0
                SetResourceKvp(KVP .. hash(item.key), encode(path))
            else
                failures = failures + 1
                if Config.Debug then print(('^3[XS-Trucking]^0 the GPS gave no usable route for %s'):format(item.key)) end
            end
        end

        send(item.key, path)
        if path then report(item, path) end
    end
    ClearGpsMultiRoute()
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
            local path = known[key]
            if path == nil then
                path = decode(GetResourceKvpString(KVP .. hash(key)))
                if path then known[key] = path end
            end

            if path ~= nil then
                found[#found + 1] = { key = key, path = path or false, meters = path and math.floor(length(path)) or nil }
                if path then report(item, path) end
            else
                queue[#queue + 1] = {
                    key = key, points = points, report = item.report == true,
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
