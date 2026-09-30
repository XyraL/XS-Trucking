local function register(name, fn)
    lib.callback.register('XS-Trucking:server:' .. name, function(src, ...)
        if not WaitForDB() then return false, 'The job is still starting up.' end
        return fn(src, ...)
    end)
end

register('board', function(src, spotId) return Jobs.Board(src, spotId) end)
register('take', function(src, spotId, routeId, hour) return Jobs.Take(src, spotId, routeId, tonumber(hour)) end)
register('hooked', function(src) return Jobs.Hooked(src) end)
register('deliver', function(src) return Jobs.Deliver(src) end)
register('return', function(src, fuel) return Jobs.Return(src, fuel) end)
register('cancel', function(src) return Jobs.Cancel(src) end)
register('run', function(src) return Jobs.State(src) end)
register('profile', function(src) return Progress.Profile(src) end)

local function catalog()
    local trucks = {}
    for i, entry in ipairs(Config.Trucks.shop) do trucks[i] = entry end
    local trailers = {}
    for i, entry in ipairs(Config.Trucks.trailers) do
        local kind = Util.TrailerType(entry.type)
        trailers[i] = { type = entry.type, typeLabel = kind and kind.label or entry.type, model = entry.model,
                        label = entry.label, price = entry.price, bonus = entry.bonus }
    end
    return {
        trucks = trucks, trailers = trailers, depot = Config.Trucks.depot, sellBack = Config.Trucks.sellBack,
        parts = Config.Parts.list, partsEnabled = Config.Parts.enabled, bodyCost = SGet('economy.bodyCost', Config.Parts.bodyCostPerPoint),
        fuelPrice = SGet('economy.fuelPrice', Config.DepotFuelPrice), upgrades = Config.Upgrades,
    }
end

register('garage', function(src)
    local list = Garage.List(src)
    list.catalog = catalog()
    local biz = Business.BySource(src)
    list.canFleet = biz and (Business.Can(src, 'fleet')) or false
    list.cash = Framework.GetMoney(src, Config.Payout.account)
    list.businessBank = biz and biz.bank or nil
    return list
end)

register('selectVehicle', function(src, id, kind) return Garage.Select(src, id, kind) end)
register('buyVehicle', function(src, kind, model, business) return Garage.Buy(src, kind, model, business == true) end)
register('sellVehicle', function(src, id) return Garage.Sell(src, id) end)
register('repair', function(src, id) return Garage.Repair(src, id) end)
register('service', function(src, id, part) return Garage.Service(src, id, part) end)
register('refuel', function(src, id) return Garage.Refuel(src, id) end)
register('upgrade', function(src, id, upgrade) return Garage.Upgrade(src, id, upgrade) end)
register('style', function(src, id, style) return Garage.Style(src, id, style) end)
register('rename', function(src, id, name) return Garage.Rename(src, id, name) end)
register('reserve', function(src, id, cid) return Garage.Reserve(src, id, cid) end)
register('sendRun', function(src, id, routeId) return Garage.SendRun(src, id, routeId) end)
register('collectRun', function(src, id) return Garage.Collect(src, id) end)

register('runRoutes', function(src)
    local out = {}
    for _, route in pairs(Spots.routes) do
        if route.enabled and not route.illegal then
            out[#out + 1] = { id = route.id, label = route.label, pay = route.pay }
        end
    end
    table.sort(out, function(a, b) return a.pay > b.pay end)
    return out
end)

register('skills', function(src)
    return { branches = Config.Skills.branches, respecCost = Config.Skills.respecCost, profile = Progress.Profile(src) }
end)
register('buySkill', function(src, id) return Progress.BuySkill(src, id) end)
register('respec', function(src) return Progress.Respec(src) end)

register('certs', function(src)
    local profile = Progress.Profile(src)
    local list = {}
    for i, cert in ipairs(Config.Certificates) do
        local types = {}
        for _, kind in ipairs(Config.TrailerTypes) do
            if kind.cert == cert.id then types[#types + 1] = kind.label end
        end
        list[i] = {
            id = cert.id, label = cert.label, description = cert.description, level = cert.level,
            deliveries = cert.deliveries, fee = cert.fee, types = types, held = profile.certs[cert.id] == true,
        }
    end
    return { list = list, profile = profile }
end)
register('earnCert', function(src, id) return Progress.EarnCert(src, id) end)

local function online()
    local set = {}
    for _, player in pairs(Framework.Players()) do
        if player.PlayerData then set[player.PlayerData.citizenid] = true end
    end
    return set
end

local function businessSnapshot(src)
    local cid = Framework.GetCitizenId(src)
    local biz = cid and Business.ByCitizen(cid)
    if not biz then return nil end

    local here = online()
    local me = biz.members[cid]
    local level = Business.Level(biz)
    local nextLevel
    for _, def in ipairs(Config.Business.levels) do
        if def.level == level.level + 1 then nextLevel = def end
    end

    local perms = {}
    for perm in pairs(Config.Business.permissions) do perms[perm] = (Business.Can(src, perm)) end

    local ranks = {}
    for grade, rank in pairs(biz.ranks) do
        ranks[#ranks + 1] = { grade = grade, name = rank.name, cut = rank.cut, permissions = rank.permissions }
    end
    table.sort(ranks, function(a, b) return a.grade < b.grade end)

    local members = {}
    for memberCid, member in pairs(biz.members) do
        members[#members + 1] = {
            citizenid = memberCid, name = member.name, grade = member.grade,
            rank = biz.ranks[member.grade] and biz.ranks[member.grade].name or '',
            online = here[memberCid] == true, owner = biz.owner == memberCid,
            deliveries = member.deliveries or 0, earned = tonumber(member.earned) or 0,
        }
    end
    table.sort(members, function(a, b)
        if a.grade ~= b.grade then return a.grade > b.grade end
        return (a.name or '') < (b.name or '')
    end)

    local daily = MySQL.query.await([[
        SELECT DATE(completed_at) AS day, SUM(company_cut) AS revenue, COUNT(*) AS loads
        FROM xs_trucking_deliveries WHERE company_id = ? AND completed_at >= DATE_SUB(CURDATE(), INTERVAL 13 DAY)
        GROUP BY DATE(completed_at) ORDER BY day
    ]], { biz.id }) or {}
    for _, row in ipairs(daily) do
        row.day = tostring(row.day):sub(1, 10)
        row.revenue = tonumber(row.revenue) or 0
        row.loads = tonumber(row.loads) or 0
    end

    local memberSlots, fleetSlots = Business.Slots(biz)
    local fleetCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM xs_trucking_owned WHERE company_id = ?', { biz.id })) or 0
    local memberCount = #members

    return {
        id = biz.id, name = biz.label, logo = biz.logo, logoHidden = biz.logo_hidden == 1, colour = biz.colour,
        motto = biz.motto, recruiting = biz.recruiting == 1, bank = tonumber(biz.bank) or 0,
        reputation = biz.reputation or 0, level = level, nextLevel = nextLevel, perkPoints = biz.perk_points or 0,
        deliveries = biz.total_deliveries or 0, perks = biz.perks, perkTree = Config.Business.perks,
        mods = Business.Mods(biz),
        slots = {
            members = memberCount, membersMax = memberSlots, fleet = fleetCount, fleetMax = fleetSlots,
            memberNext = Config.Business.members.upgrades[(biz.member_tier or 0) + 1],
            fleetNext = Config.Business.fleet.upgrades[(biz.fleet_tier or 0) + 1],
        },
        me = { citizenid = cid, grade = me and me.grade or 0, owner = biz.owner == cid, perms = perms },
        ranks = ranks, maxRanks = Config.Business.maxRanks, permissions = Config.Business.permissions,
        members = members, daily = daily, ledger = Business.Ledger(biz.id, 25),
        runs = Config.Business.runs,
    }
end

register('business', function(src)
    local snapshot = businessSnapshot(src)
    if snapshot then return snapshot end
    return {
        none = true, foundingCost = SGet('business.foundingCost', Config.Business.foundingCost),
        enabled = Config.Business.enabled, nameLength = Config.Business.nameLength, logoHosts = Config.Business.logoHosts,
    }
end)

register('foundBusiness', function(src, name) return Business.Found(src, name) end)
register('businessInvite', function(src, target) return Business.Invite(src, target) end)
register('businessAccept', function(src) return Business.Accept(src) end)
register('businessLeave', function(src) return Business.Leave(src) end)
register('businessKick', function(src, cid) return Business.Kick(src, cid) end)
register('businessGrade', function(src, cid, grade) return Business.SetGrade(src, cid, grade) end)
register('businessRanks', function(src, ranks) return Business.SaveRanks(src, ranks) end)
register('businessProfile', function(src, data) return Business.SaveProfile(src, data) end)
register('businessDeposit', function(src, amount) return Business.Deposit(src, amount) end)
register('businessWithdraw', function(src, amount) return Business.Withdraw(src, amount) end)
register('businessPerk', function(src, perk) return Business.BuyPerk(src, perk) end)
register('businessSlots', function(src, which) return Business.BuySlots(src, which) end)
register('businessTransfer', function(src, cid) return Business.TransferOwner(src, cid) end)
register('businessDisband', function(src) return Business.Disband(src) end)
register('businessLedger', function(src)
    local biz = Business.BySource(src)
    return biz and Business.Ledger(biz.id, Config.Business.ledgerLimit) or {}
end)

register('nearbyPlayers', function(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return {} end
    local here = GetEntityCoords(ped)
    local out = {}
    for _, player in pairs(Framework.Players()) do
        local data = player.PlayerData
        local other = data and data.source
        if other and other ~= src then
            local otherPed = GetPlayerPed(other)
            if otherPed ~= 0 and #(GetEntityCoords(otherPed) - here) < 8.0 then
                out[#out + 1] = { source = other, name = Framework.GetName(other) }
            end
        end
    end
    return out
end)

local leaderboardCache, leaderboardAt = nil, 0

register('leaderboards', function(src)
    if leaderboardCache and os.time() - leaderboardAt < 30 then return leaderboardCache end

    local limit = Config.Leaderboards.limit
    local function numbers(rows, keys)
        for _, row in ipairs(rows) do
            for _, key in ipairs(keys) do row[key] = tonumber(row[key]) or 0 end
        end
        return rows
    end

    local earners = numbers(MySQL.query.await(
        'SELECT name, level, total_completed AS loads, total_earned AS earned FROM xs_trucking_stats ORDER BY total_earned DESC LIMIT ?',
        { limit }) or {}, { 'level', 'loads', 'earned' })

    local week = numbers(MySQL.query.await([[
        SELECT s.name, COUNT(*) AS loads, SUM(d.driver_cut) AS earned, ROUND(AVG(d.trip_rating)) AS rating
        FROM xs_trucking_deliveries d LEFT JOIN xs_trucking_stats s ON s.citizenid = d.citizenid
        WHERE d.completed_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) AND d.role = 'driver'
        GROUP BY d.citizenid, s.name ORDER BY loads DESC LIMIT ?
    ]], { limit }) or {}, { 'loads', 'earned', 'rating' })

    local businesses = numbers(MySQL.query.await([[
        SELECT c.id, c.label AS name, IF(c.logo_hidden = 1, '', c.logo) AS logo, c.colour, c.reputation, c.total_deliveries AS loads,
            (SELECT COUNT(*) FROM xs_trucking_company_members m WHERE m.company_id = c.id) AS members,
            (SELECT COALESCE(SUM(d.company_cut), 0) FROM xs_trucking_deliveries d
             WHERE d.company_id = c.id AND d.completed_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)) AS week
        FROM xs_trucking_companies c ORDER BY c.reputation DESC LIMIT ?
    ]], { limit }) or {}, { 'reputation', 'loads', 'members', 'week' })

    leaderboardCache = { earners = earners, week = week, businesses = businesses }
    leaderboardAt = os.time()
    return leaderboardCache
end)

register('history', function(src)
    local cid = Framework.GetCitizenId(src)
    if not cid then return { rows = {}, daily = {} } end

    local rows = MySQL.query.await([[
        SELECT id, label, cargo_type, base_payout, final_payout, driver_cut, company_cut, truck_bonus_pct, hot_bonus_pct,
            multistop_bonus_pct, rating_bonus_pct, skill_bonus_pct, coop_bonus_pct, spoiled, trip_rating, stop_count, xp,
            distance_m, duration_seconds, role, illegal, UNIX_TIMESTAMP(completed_at) AS ts
        FROM xs_trucking_deliveries WHERE citizenid = ? ORDER BY id DESC LIMIT 30
    ]], { cid }) or {}
    for _, row in ipairs(rows) do
        for key, value in pairs(row) do
            if key ~= 'label' and key ~= 'cargo_type' and key ~= 'role' then row[key] = tonumber(value) or value end
        end
    end

    local daily = MySQL.query.await([[
        SELECT DATE(completed_at) AS day, SUM(driver_cut) AS earned, COUNT(*) AS loads
        FROM xs_trucking_deliveries WHERE citizenid = ? AND completed_at >= DATE_SUB(CURDATE(), INTERVAL 13 DAY)
        GROUP BY DATE(completed_at) ORDER BY day
    ]], { cid }) or {}
    for _, row in ipairs(daily) do
        row.day = tostring(row.day):sub(1, 10)
        row.earned = tonumber(row.earned) or 0
        row.loads = tonumber(row.loads) or 0
    end

    return { rows = rows, daily = daily }
end)
