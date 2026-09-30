Settings = {}

local cache = {}

local SCHEMA = {
    { key = 'economy.payoutMult', label = 'Pay multiplier', group = 'Economy', type = 'number', min = 0, max = 500, suffix = '%', default = 100,
      help = 'Scales the pay of every load.' },
    { key = 'economy.xpMult', label = 'XP multiplier', group = 'Economy', type = 'number', min = 0, max = 500, suffix = '%', default = 100 },
    { key = 'economy.fuelPrice', label = 'Depot fuel, per percent', group = 'Economy', type = 'number', min = 0, max = 1000, prefix = '$', path = 'DepotFuelPrice' },
    { key = 'economy.bodyCost', label = 'Body repair, per point', group = 'Economy', type = 'number', min = 0, max = 1000, prefix = '$', path = 'Parts.bodyCostPerPoint' },
    { key = 'economy.cancelFee', label = 'Fee for dropping a load', group = 'Economy', type = 'number', min = 0, max = 100000, prefix = '$', path = 'Job.cancelFee' },

    { key = 'bonus.multiStop', label = 'Multi-stop bonus', group = 'Bonuses', type = 'number', min = 0, max = 300, suffix = '%', path = 'Pay.multiStopBonus' },
    { key = 'bonus.ratingBonus', label = 'High-rating bonus', group = 'Bonuses', type = 'number', min = 0, max = 100, suffix = '%', path = 'Pay.rating.bonus' },
    { key = 'bonus.ratingPenalty', label = 'Low-rating penalty', group = 'Bonuses', type = 'number', min = 0, max = 100, suffix = '%', path = 'Pay.rating.penalty' },
    { key = 'bonus.latePay', label = 'Pay when a timed load is late', group = 'Bonuses', type = 'number', min = 0, max = 100, suffix = '%', path = 'Job.latePayPercent' },

    { key = 'hot.enabled', label = 'Hot loads', group = 'Hot loads', type = 'bool', path = 'Pay.hot.enabled' },
    { key = 'hot.bonus', label = 'Hot load bonus', group = 'Hot loads', type = 'number', min = 0, max = 500, suffix = '%', path = 'Pay.hot.bonus' },
    { key = 'hot.rotateMinutes', label = 'Swap every', group = 'Hot loads', type = 'number', min = 1, max = 720, suffix = ' min', path = 'Pay.hot.rotateMinutes' },
    { key = 'hot.count', label = 'Hot loads at once', group = 'Hot loads', type = 'number', min = 0, max = 10, path = 'Pay.hot.count' },

    { key = 'coop.convoyBonus', label = 'Convoy bonus per truck', group = 'Co-op', type = 'number', min = 0, max = 100, suffix = '%', path = 'Coop.convoy.bonusPerTruck' },
    { key = 'coop.escortCut', label = 'Escort pay', group = 'Co-op', type = 'number', min = 0, max = 100, suffix = '%', path = 'Coop.escort.cut' },
    { key = 'coop.codriverCut', label = 'Co-driver pay', group = 'Co-op', type = 'number', min = 0, max = 100, suffix = '%', path = 'Coop.codriver.cut' },

    { key = 'illegal.enabled', label = 'Illegal runs', group = 'Illegal runs', type = 'bool', path = 'Illegal.enabled' },
    { key = 'illegal.tipChance', label = 'Tip-off chance', group = 'Illegal runs', type = 'number', min = 0, max = 100, suffix = '%', path = 'Illegal.tipChance' },
    { key = 'illegal.heatPerRun', label = 'Heat per run', group = 'Illegal runs', type = 'number', min = 0, max = 100, path = 'Illegal.heatPerRun' },
    { key = 'illegal.decayPerHour', label = 'Heat lost per hour', group = 'Illegal runs', type = 'number', min = 0, max = 100, path = 'Illegal.decayPerHour' },

    { key = 'business.foundingCost', label = 'Starting a business', group = 'Businesses', type = 'number', min = 0, max = 10000000, prefix = '$', path = 'Business.foundingCost' },
    { key = 'business.runPay', label = 'Fleet run pay', group = 'Businesses', type = 'number', min = 0, max = 200, suffix = '%', path = 'Business.runs.payPercent' },
    { key = 'business.runMinutes', label = 'Fleet run length', group = 'Businesses', type = 'number', min = 1, max = 480, suffix = ' min', path = 'Business.runs.minutes' },
}

local BY_KEY = {}
for _, def in ipairs(SCHEMA) do BY_KEY[def.key] = def end

local function fromConfig(def)
    if not def.path then return def.default end
    local node = Config
    for part in def.path:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return def.default end
        node = node[part]
    end
    if node == nil then return def.default end
    return node
end

local function coerce(def, raw)
    if def.type == 'bool' then return raw == true or raw == 'true' or raw == 1 or raw == '1' end
    return tonumber(raw)
end

function Settings.Load()
    local rows = MySQL.query.await('SELECT `key`, `value` FROM xs_trucking_settings') or {}
    cache = {}
    for _, row in ipairs(rows) do
        local def = BY_KEY[row.key]
        if def then cache[row.key] = coerce(def, row.value) end
    end
end

function Settings.Get(key)
    if cache[key] ~= nil then return cache[key] end
    local def = BY_KEY[key]
    if not def then return nil end
    return fromConfig(def)
end

function SGet(key, fallback)
    local value = Settings.Get(key)
    if value == nil then return fallback end
    return value
end

function Settings.Set(key, value)
    local def = BY_KEY[key]
    if not def then return false, 'Unknown setting.' end

    local coerced = coerce(def, value)
    if def.type == 'number' then
        if not coerced then return false, 'Not a number.' end
        if def.min and coerced < def.min then return false, ('The lowest is %s.'):format(def.min) end
        if def.max and coerced > def.max then return false, ('The highest is %s.'):format(def.max) end
    end

    cache[key] = coerced
    MySQL.query.await('INSERT INTO xs_trucking_settings (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)',
        { key, tostring(coerced) })
    return true
end

function Settings.Reset(key)
    if not BY_KEY[key] then return false, 'Unknown setting.' end
    cache[key] = nil
    MySQL.query.await('DELETE FROM xs_trucking_settings WHERE `key` = ?', { key })
    return true
end

function Settings.List()
    local groups, order = {}, {}

    for _, def in ipairs(SCHEMA) do
        if not groups[def.group] then
            groups[def.group] = {}
            order[#order + 1] = def.group
        end

        local list = groups[def.group]
        list[#list + 1] = {
            key = def.key, label = def.label, type = def.type, min = def.min, max = def.max,
            prefix = def.prefix, suffix = def.suffix, help = def.help,
            value = Settings.Get(def.key), default = fromConfig(def), changed = cache[def.key] ~= nil,
        }
    end

    local out = {}
    for i, name in ipairs(order) do out[i] = { group = name, items = groups[name] } end
    return out
end
