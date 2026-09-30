Util = {}

function Util.Decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return nil end

    local ok, decoded = pcall(json.decode, value)
    if ok then return decoded end
    return nil
end

function Util.Truthy(value)
    return value == true or value == 1 or value == '1'
end

function Util.Clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

function Util.Round(value, places)
    local mult = 10 ^ (places or 0)
    return math.floor((tonumber(value) or 0) * mult + 0.5) / mult
end

function Util.Trim(value)
    return (tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

function Util.Text(value, max)
    local text = Util.Trim(value):gsub('[%c]', '')
    if max and #text > max then text = text:sub(1, max) end
    return text
end

function Util.Money(amount)
    local n = math.floor(tonumber(amount) or 0)
    local text = tostring(math.abs(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (n < 0 and '-' or '') .. (Config.Currency or '$') .. text
end

function Util.Point(point)
    if type(point) ~= 'table' then return nil end

    local x, y, z = tonumber(point.x), tonumber(point.y), tonumber(point.z)
    if not x or not y or not z then return nil end

    return { x = x + 0.0, y = y + 0.0, z = z + 0.0, h = (tonumber(point.h) or 0.0) + 0.0 }
end

function Util.Points(list, max)
    local out = {}
    for _, point in ipairs(type(list) == 'table' and list or {}) do
        local p = Util.Point(point)
        if p then out[#out + 1] = p end
        if max and #out >= max then break end
    end
    return out
end

function Util.Distance(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Util.Distance2D(a, b)
    if not a or not b then return math.huge end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function Util.Near(a, b, radius)
    if not a or not b then return false end
    return Util.Distance2D(a, b) <= radius and math.abs((a.z or 0) - (b.z or 0)) <= 8.0
end

function Util.AngleDiff(a, b)
    local d = math.abs(((a or 0) - (b or 0)) % 360)
    return d > 180 and 360 - d or d
end

function Util.TrailerType(id)
    for _, entry in ipairs(Config.TrailerTypes) do
        if entry.id == id then return entry end
    end
    return nil
end

function Util.Certificate(id)
    for _, entry in ipairs(Config.Certificates) do
        if entry.id == id then return entry end
    end
    return nil
end

function Util.ShopTruck(model)
    for _, entry in ipairs(Config.Trucks.shop) do
        if entry.model == model then return entry end
    end
    return nil
end

function Util.ShopTrailer(model)
    for _, entry in ipairs(Config.Trucks.trailers) do
        if entry.model == model then return entry end
    end
    return nil
end

function Util.XpForLevel(level)
    level = math.floor(tonumber(level) or 1)
    if level <= 1 then return 0 end
    return math.floor(Config.Levels.base * ((level - 1) ^ Config.Levels.exponent))
end

function Util.LevelForXp(xp)
    xp = tonumber(xp) or 0
    local level = 1
    for n = 2, Config.Levels.max do
        if xp >= Util.XpForLevel(n) then level = n else break end
    end
    return level
end

function Util.LevelTitle(level)
    local title, best = 'Driver', 0
    for from, name in pairs(Config.Levels.titles) do
        if from <= level and from > best then title, best = name, from end
    end
    return title
end

function Util.RouteLength(route, origin)
    local total, prev = 0, route.pickup or origin
    for _, stop in ipairs(route.stops or {}) do
        if prev then total = total + Util.Distance2D(prev, stop) end
        prev = stop
    end
    return total
end
