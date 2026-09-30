local function audit(src, action, detail)
    MySQL.insert('INSERT INTO xs_trucking_admin_log (citizenid, name, action, detail) VALUES (?, ?, ?, ?)', {
        Framework.GetCitizenId(src) or '', Framework.GetName(src) or '', action, Util.Text(detail or '', 255),
    })
end

local function guarded(name, fn)
    lib.callback.register('XS-Trucking:server:' .. name, function(src, ...)
        if not Framework.IsAdmin(src) then return false, 'You are not allowed to do that.' end
        if not WaitForDB() then return false, 'The job is still starting up.' end
        return fn(src, ...)
    end)
end

local function builderData()
    local data = Spots.Builder()
    local types = {}
    for i, kind in ipairs(Config.TrailerTypes) do
        types[i] = { id = kind.id, label = kind.label, models = kind.models, cert = kind.cert }
    end
    local certs = {}
    for i, cert in ipairs(Config.Certificates) do certs[i] = { id = cert.id, label = cert.label } end

    data.meta = {
        types = types, certs = certs, maxLevel = Config.Levels.max, depotTruck = Config.Trucks.depot.model,
        convoy = Config.Coop.convoy.enabled and Config.Coop.convoy.maxTrucks or 0, escorts = Config.Coop.escort.enabled,
        illegal = Config.Illegal.enabled, suggest = Config.Pay.suggest,
    }
    return data
end

guarded('builder', function() return builderData() end)

guarded('saveSpot', function(src, draft)
    local ok, result = Spots.SaveSpot(src, draft)
    if not ok then return false, result end
    audit(src, 'saveSpot', ('#%d %s'):format(result, Spots.spots[result].name))
    return true, { id = result, data = builderData() }
end)

guarded('deleteSpot', function(src, id)
    local spot = Spots.Get(id)
    local ok, err = Spots.DeleteSpot(id)
    if not ok then return false, err end
    audit(src, 'deleteSpot', spot and spot.name or tostring(id))
    return true, builderData()
end)

guarded('saveRoute', function(src, draft)
    local ok, result = Spots.SaveRoute(src, draft)
    if not ok then return false, result end
    audit(src, 'saveRoute', ('#%d %s'):format(result, Spots.routes[result].label))
    return true, { id = result, data = builderData() }
end)

guarded('deleteRoute', function(src, id)
    local route = Spots.Route(id)
    local ok, err = Spots.DeleteRoute(id)
    if not ok then return false, err end
    audit(src, 'deleteRoute', route and route.label or tostring(id))
    return true, builderData()
end)

guarded('suggestPay', function(_, draft)
    if type(draft) ~= 'table' then return nil end
    local spot = Spots.Get(draft.spot)
    local route = {
        type = Util.TrailerType(draft.type) and draft.type or 'dryvan',
        pickup = Util.Point(draft.pickup),
        stops = Util.Points(draft.stops, 8),
    }
    if #route.stops == 0 then return nil end
    local origin = route.pickup or (spot and spot.trailerBays[1]) or nil
    return Spots.SuggestPay(route, origin)
end)

local function number(value)
    return tonumber(value) or 0
end

guarded('adminOverview', function()
    local drivers = MySQL.single.await([[
        SELECT COUNT(*) AS drivers, COALESCE(SUM(total_completed), 0) AS loads, COALESCE(SUM(total_earned), 0) AS earned
        FROM xs_trucking_stats
    ]]) or {}
    local today = MySQL.single.await([[
        SELECT COUNT(*) AS loads, COALESCE(SUM(final_payout), 0) AS paid, COALESCE(SUM(illegal), 0) AS illegal
        FROM xs_trucking_deliveries WHERE completed_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
    ]]) or {}
    local fleet = MySQL.single.await([[
        SELECT COUNT(*) AS vehicles, COALESCE(AVG(`condition`), 100) AS condition_avg,
            COALESCE(SUM(CASE WHEN dispatch_ready_at IS NOT NULL THEN 1 ELSE 0 END), 0) AS out_now
        FROM xs_trucking_owned
    ]]) or {}
    local businesses = MySQL.single.await('SELECT COUNT(*) AS total, COALESCE(SUM(bank), 0) AS bank FROM xs_trucking_companies') or {}
    local daily = MySQL.query.await([[
        SELECT DATE(completed_at) AS day, COUNT(*) AS loads, SUM(final_payout) AS paid
        FROM xs_trucking_deliveries WHERE completed_at >= DATE_SUB(CURDATE(), INTERVAL 13 DAY)
        GROUP BY DATE(completed_at) ORDER BY day
    ]]) or {}
    for _, row in ipairs(daily) do
        row.day = tostring(row.day):sub(1, 10)
        row.loads = number(row.loads)
        row.paid = number(row.paid)
    end

    local spots, routes = 0, 0
    for _ in pairs(Spots.spots) do spots = spots + 1 end
    for _ in pairs(Spots.routes) do routes = routes + 1 end

    return {
        drivers = number(drivers.drivers), loads = number(drivers.loads), earned = number(drivers.earned),
        todayLoads = number(today.loads), todayPaid = number(today.paid), todayIllegal = number(today.illegal),
        vehicles = number(fleet.vehicles), condition = math.floor(number(fleet.condition_avg)), fleetOut = number(fleet.out_now),
        businesses = number(businesses.total), businessBank = number(businesses.bank),
        spots = spots, routes = routes, active = Jobs.List(), daily = daily,
    }
end)

guarded('adminRuns', function() return Jobs.List() end)

guarded('adminPlayers', function(_, query)
    query = Util.Trim(query)
    local rows
    if #query >= 2 then
        local like = '%' .. query .. '%'
        rows = MySQL.query.await([[
            SELECT citizenid, name, level, xp, total_completed, total_earned, rating_sum, heat, heat_at
            FROM xs_trucking_stats WHERE citizenid LIKE ? OR name LIKE ? ORDER BY total_earned DESC LIMIT 25
        ]], { like, like }) or {}
    else
        rows = MySQL.query.await([[
            SELECT citizenid, name, level, xp, total_completed, total_earned, rating_sum, heat, heat_at
            FROM xs_trucking_stats ORDER BY total_earned DESC LIMIT 25
        ]]) or {}
    end

    local online = {}
    for _, player in pairs(Framework.Players()) do
        if player.PlayerData then online[player.PlayerData.citizenid] = player.PlayerData.source end
    end

    for _, row in ipairs(rows) do
        row.rating = Progress.Rating(row)
        row.heat = Progress.Heat(row)
        row.level = Util.LevelForXp(row.xp)
        row.online = online[row.citizenid] ~= nil
        row.source = online[row.citizenid]
    end
    return rows
end)

guarded('adminPlayer', function(_, cid)
    local stats = MySQL.single.await('SELECT * FROM xs_trucking_stats WHERE citizenid = ?', { cid })
    if not stats then return nil end

    local vehicles = MySQL.query.await('SELECT id, kind, model, label, nickname, plate, `condition`, company_id FROM xs_trucking_owned WHERE citizenid = ? ORDER BY id', { cid }) or {}
    local recent = MySQL.query.await([[
        SELECT label, final_payout, driver_cut, trip_rating, illegal, role, UNIX_TIMESTAMP(completed_at) AS ts
        FROM xs_trucking_deliveries WHERE citizenid = ? ORDER BY id DESC LIMIT 12
    ]], { cid }) or {}
    for _, row in ipairs(recent) do row.ts = number(row.ts) end

    local biz = Business.ByCitizen(cid)
    local ranks = Progress.Skills(cid)
    local _, spent = Progress.Points({ level = Util.LevelForXp(stats.xp) }, ranks)

    return {
        citizenid = cid, name = stats.name, xp = stats.xp, level = Util.LevelForXp(stats.xp),
        loads = stats.total_completed, earned = stats.total_earned, rating = Progress.Rating(stats), heat = Progress.Heat(stats),
        illegalRuns = stats.illegal_runs or 0, skills = ranks, spent = spent, certs = Progress.Certs(cid),
        vehicles = vehicles, recent = recent, business = Business.Public(biz),
        certList = Config.Certificates, maxLevel = Config.Levels.max,
    }
end)

guarded('adminPlayerAction', function(src, cid, action, value)
    if not cid or not MySQL.scalar.await('SELECT 1 FROM xs_trucking_stats WHERE citizenid = ?', { cid }) then
        return false, 'No trucking record for that player.'
    end

    if action == 'level' then
        local level = math.floor(Util.Clamp(value, 1, Config.Levels.max))
        MySQL.update.await('UPDATE xs_trucking_stats SET xp = ?, level = ? WHERE citizenid = ?', { Util.XpForLevel(level), level, cid })
    elseif action == 'xp' then
        local amount = math.floor(tonumber(value) or 0)
        MySQL.update.await('UPDATE xs_trucking_stats SET xp = GREATEST(0, xp + ?) WHERE citizenid = ?', { amount, cid })
    elseif action == 'cert' then
        if type(value) ~= 'table' or not Util.Certificate(value.id) then return false, 'Unknown certificate.' end
        Progress.GrantCert(cid, value.id, value.grant == true)
    elseif action == 'resetSkills' then
        Progress.ResetSkills(cid)
    elseif action == 'heat' then
        Progress.SetHeat(cid, tonumber(value) or 0)
    elseif action == 'rating' then
        MySQL.update.await('UPDATE xs_trucking_stats SET rating_sum = total_completed * 100 WHERE citizenid = ?', { cid })
    elseif action == 'clearRun' then
        local ok, err = Jobs.Clear(cid)
        if not ok then return false, err end
    else
        return false, 'Unknown action.'
    end

    audit(src, 'player:' .. tostring(action), ('%s %s'):format(cid, type(value) == 'table' and json.encode(value) or tostring(value or '')))
    return true
end)

guarded('adminBusinesses', function()
    local rows = MySQL.query.await([[
        SELECT c.id, c.label AS name, c.owner, c.bank, c.reputation, c.total_deliveries AS loads, c.logo, c.logo_hidden, c.colour, c.motto,
            (SELECT COUNT(*) FROM xs_trucking_company_members m WHERE m.company_id = c.id) AS members,
            (SELECT COUNT(*) FROM xs_trucking_owned o WHERE o.company_id = c.id) AS trucks
        FROM xs_trucking_companies c ORDER BY c.label
    ]]) or {}
    for _, row in ipairs(rows) do
        row.bank = number(row.bank)
        row.members = number(row.members)
        row.trucks = number(row.trucks)
        row.logoHidden = number(row.logo_hidden) == 1
        row.ownerName = Framework.NameByCitizenId(row.owner) or row.owner
    end
    return rows
end)

guarded('adminBusiness', function(_, id)
    local biz = Business.Get(id)
    if not biz then return nil end
    local members = {}
    for cid, member in pairs(biz.members) do
        members[#members + 1] = { citizenid = cid, name = member.name, grade = member.grade,
            rank = biz.ranks[member.grade] and biz.ranks[member.grade].name or '', deliveries = member.deliveries or 0 }
    end
    table.sort(members, function(a, b) return a.grade > b.grade end)
    return {
        id = biz.id, name = biz.label, logo = biz.logo, logoHidden = biz.logo_hidden == 1, colour = biz.colour, motto = biz.motto,
        bank = number(biz.bank), reputation = biz.reputation or 0, level = Business.Level(biz), members = members,
        ledger = Business.Ledger(biz.id, 40),
        fleet = MySQL.query.await('SELECT id, model, label, nickname, plate, `condition` FROM xs_trucking_owned WHERE company_id = ?', { biz.id }) or {},
    }
end)

guarded('adminBusinessAction', function(src, id, action, value)
    local biz = Business.Get(id)
    if not biz then return false, 'That business is gone.' end

    if action == 'hideLogo' then
        Business.SetLogoHidden(biz.id, true)
    elseif action == 'showLogo' then
        Business.SetLogoHidden(biz.id, false)
    elseif action == 'removeLogo' then
        MySQL.update.await("UPDATE xs_trucking_companies SET logo = '', logo_hidden = 0 WHERE id = ?", { biz.id })
        biz.logo, biz.logo_hidden = '', 0
    elseif action == 'bank' then
        local amount = math.max(0, math.floor(tonumber(value) or 0))
        MySQL.update.await('UPDATE xs_trucking_companies SET bank = ? WHERE id = ?', { amount, biz.id })
        biz.bank = amount
    elseif action == 'rename' then
        local name = Util.Text(value, Config.Business.nameLength[2])
        if #name < Config.Business.nameLength[1] then return false, 'That name is too short.' end
        MySQL.update.await('UPDATE xs_trucking_companies SET name = ?, label = ? WHERE id = ?', { name, name, biz.id })
        biz.name, biz.label = name, name
    elseif action == 'disband' then
        Business.DisbandById(biz.id)
    else
        return false, 'Unknown action.'
    end

    audit(src, 'business:' .. tostring(action), ('#%d %s %s'):format(biz.id, biz.label or '', tostring(value or '')))
    return true
end)

guarded('adminFleet', function(_, filter)
    local where = ''
    if filter == 'damaged' then where = 'WHERE `condition` < 60' end
    if filter == 'out' then where = 'WHERE dispatch_ready_at IS NOT NULL' end
    if filter == 'business' then where = 'WHERE company_id IS NOT NULL' end

    local rows = MySQL.query.await(('SELECT id, citizenid, company_id, kind, model, label, nickname, plate, `condition`, dispatch_ready_at FROM xs_trucking_owned %s ORDER BY id DESC LIMIT 80'):format(where)) or {}
    for _, row in ipairs(rows) do
        row.ownerName = Framework.NameByCitizenId(row.citizenid) or row.citizenid
        local biz = row.company_id and Business.Get(row.company_id)
        row.businessName = biz and biz.label or nil
        row.out = row.dispatch_ready_at ~= nil
        row.dispatch_ready_at = nil
    end
    return rows
end)

guarded('adminVehicleAction', function(src, id, action)
    id = tonumber(id)
    if not id then return false, 'Unknown vehicle.' end
    if Jobs.UsingOwned(id) and action == 'delete' then return false, 'It is out on a load right now.' end

    if action == 'repair' then
        local row = Garage.Row(id)
        if not row then return false, 'That vehicle is gone.' end
        local parts = Garage.Parts(row)
        for _, part in ipairs(Config.Parts.list) do parts[part.id] = 100 end
        parts.fuel = 100
        MySQL.update.await('UPDATE xs_trucking_owned SET `condition` = 100, maintenance = ? WHERE id = ?', { json.encode(parts), id })
    elseif action == 'recall' then
        MySQL.update.await('UPDATE xs_trucking_owned SET dispatch_ready_at = NULL, dispatch_contract_id = NULL, dispatch_payout = NULL WHERE id = ?', { id })
    elseif action == 'delete' then
        MySQL.update.await('DELETE FROM xs_trucking_owned WHERE id = ?', { id })
    else
        return false, 'Unknown action.'
    end

    audit(src, 'vehicle:' .. tostring(action), tostring(id))
    return true
end)

guarded('adminSettings', function() return Settings.List() end)

guarded('adminSetSetting', function(src, key, value)
    local ok, err = Settings.Set(key, value)
    if ok then audit(src, 'setting', ('%s = %s'):format(tostring(key), tostring(value))) end
    return ok, err
end)

guarded('adminResetSetting', function(src, key)
    local ok, err = Settings.Reset(key)
    if ok then audit(src, 'setting', ('%s reset'):format(tostring(key))) end
    return ok, err
end)

guarded('adminLogs', function()
    local loads = MySQL.query.await([[
        SELECT d.label, d.final_payout, d.driver_cut, d.company_cut, d.trip_rating, d.illegal, d.role, d.citizenid,
            s.name, UNIX_TIMESTAMP(d.completed_at) AS ts
        FROM xs_trucking_deliveries d LEFT JOIN xs_trucking_stats s ON s.citizenid = d.citizenid
        ORDER BY d.id DESC LIMIT 60
    ]]) or {}
    for _, row in ipairs(loads) do
        row.ts = number(row.ts)
        row.name = row.name or row.citizenid
    end

    local admin = MySQL.query.await('SELECT name, action, detail, UNIX_TIMESTAMP(created_at) AS ts FROM xs_trucking_admin_log ORDER BY id DESC LIMIT 60') or {}
    for _, row in ipairs(admin) do row.ts = number(row.ts) end

    return { loads = loads, admin = admin }
end)
