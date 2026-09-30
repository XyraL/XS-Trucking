Garage = {}

local selected = {}

local PART_IDS = {}
for _, part in ipairs(Config.Parts.list) do PART_IDS[part.id] = part end

local function randomPlate()
    local prefix = tostring(Config.Job.platePrefix or 'XSTR'):upper():sub(1, 5)
    local digits = 8 - #prefix
    local out = prefix
    for _ = 1, digits do out = out .. tostring(math.random(0, 9)) end
    return out
end

function Garage.Parts(row)
    local parts = { fuel = 100, odometer = 0 }
    for id in pairs(PART_IDS) do parts[id] = 100 end
    local stored = row and Util.Decode(row.maintenance)
    if type(stored) == 'table' then
        for k, v in pairs(stored) do
            if type(v) == 'number' then parts[k] = v end
        end
    end
    return parts
end

local function saveParts(id, parts)
    MySQL.update.await('UPDATE xs_trucking_owned SET maintenance = ? WHERE id = ?', { json.encode(parts), id })
end

function Garage.Row(id)
    id = tonumber(id)
    if not id then return nil end
    return MySQL.single.await('SELECT * FROM xs_trucking_owned WHERE id = ?', { id })
end

function Garage.Plate(row)
    if row.plate and row.plate ~= '' then return row.plate end
    local plate
    for _ = 1, 20 do
        plate = randomPlate()
        if not MySQL.scalar.await('SELECT 1 FROM xs_trucking_owned WHERE plate = ?', { plate }) then break end
    end
    MySQL.update.await('UPDATE xs_trucking_owned SET plate = ? WHERE id = ?', { plate, row.id })
    row.plate = plate
    return plate
end

function Garage.Usable(src, cid, row)
    if not row then return false end
    if row.company_id then
        local biz = Business.ByCitizen(cid)
        if not biz or biz.id ~= row.company_id then return false end
        if row.reserved_for and row.reserved_for ~= '' and row.reserved_for ~= cid then return false end
        return true, biz
    end
    return row.citizenid == cid
end

local function describe(row, cid)
    local shop = row.kind == 'truck' and Util.ShopTruck(row.model) or Util.ShopTrailer(row.model)
    return {
        id = row.id,
        kind = row.kind,
        model = row.model,
        label = row.label,
        nickname = row.nickname,
        plate = row.plate,
        trailerType = row.trailer_type,
        business = row.company_id,
        reservedFor = row.reserved_for,
        mine = row.citizenid == cid,
        condition = row.condition,
        parts = Garage.Parts(row),
        upgrades = Util.Decode(row.upgrades) or {},
        livery = Util.Decode(row.livery) or {},
        bonus = shop and shop.bonus or 0,
        value = shop and math.floor(shop.price * (Config.Trucks.sellBack or 50) / 100) or 0,
        run = row.dispatch_ready_at and {
            routeId = tonumber(row.dispatch_contract_id),
            readyAt = math.floor((tonumber(row.dispatch_ready_at) or 0) / 1000),
            pay = row.dispatch_payout or 0,
        } or nil,
    }
end

function Garage.List(src)
    local cid = Framework.GetCitizenId(src)
    if not cid or not WaitForDB() then return { personal = {}, business = {} } end

    local personal = {}
    for _, row in ipairs(MySQL.query.await('SELECT * FROM xs_trucking_owned WHERE citizenid = ? AND company_id IS NULL ORDER BY id', { cid }) or {}) do
        personal[#personal + 1] = describe(row, cid)
    end

    local business = {}
    local biz = Business.ByCitizen(cid)
    if biz then
        for _, row in ipairs(MySQL.query.await('SELECT * FROM xs_trucking_owned WHERE company_id = ? ORDER BY id', { biz.id }) or {}) do
            business[#business + 1] = describe(row, cid)
        end
    end

    local pick = selected[src] or {}
    return { personal = personal, business = business, truck = pick.truck, trailer = pick.trailer }
end

function Garage.Select(src, id, kind)
    kind = kind == 'trailer' and 'trailer' or 'truck'
    selected[src] = selected[src] or {}

    if not id then
        selected[src][kind] = nil
        return true
    end

    local cid = Framework.GetCitizenId(src)
    local row = Garage.Row(id)
    if not row or row.kind ~= kind or not Garage.Usable(src, cid, row) then return false, 'You cannot use that one.' end
    if row.dispatch_ready_at then return false, 'It is out on a fleet run.' end
    if kind == 'truck' and row.condition <= 0 then return false, 'It needs repairing first.' end

    selected[src][kind] = row.id
    return true
end

function Garage.Selected(src, kind)
    local pick = selected[src]
    local id = pick and pick[kind]
    if not id then return nil end

    local cid = Framework.GetCitizenId(src)
    local row = Garage.Row(id)
    if not row or row.kind ~= kind or not Garage.Usable(src, cid, row) or row.dispatch_ready_at then
        pick[kind] = nil
        return nil
    end
    return row
end

local NOTES = { repair = 'Body repair', service = 'Service', fuel = 'Fuel', upgrade = 'Upgrade', style = 'Styling' }

local function pay(src, cid, row, cost, reason)
    cost = math.floor(cost)
    if cost <= 0 then return true end

    if row.company_id then
        local can, biz = Business.Can(src, 'fleet')
        if not biz or biz.id ~= row.company_id then return false, 'That truck is not your business.' end
        if not can then return false, 'Your rank cannot spend on business trucks.' end
        if not Business.Charge(src, biz, cost, 'fleet', ('%s · %s'):format(NOTES[reason] or reason, row.nickname or row.label)) then
            return false, ('That costs %s and the business bank is short.'):format(Util.Money(cost))
        end
        return true
    end

    if row.citizenid ~= cid then return false, 'That is not yours.' end
    if not Framework.RemoveMoney(src, Config.Payout.account, cost, 'XS-Trucking:' .. (reason or 'garage')) then
        return false, ('That costs %s.'):format(Util.Money(cost))
    end
    return true
end

local function discount(cid, stat, cost, row)
    local pct = Progress.Mod(cid, stat)
    if stat == 'repair' and row and row.company_id then
        local biz = Business.Get(row.company_id)
        pct = pct + Business.Mods(biz).repair
    end
    return math.floor(cost * (1 - math.min(pct, 80) / 100))
end

local function ownRow(src, id)
    local cid = Framework.GetCitizenId(src)
    if not cid then return nil, nil, 'No character loaded.' end
    local row = Garage.Row(id)
    if not row then return nil, nil, 'That vehicle is gone.' end
    if not Garage.Usable(src, cid, row) then return nil, nil, 'That is not yours to change.' end
    return row, cid
end

function Garage.Buy(src, kind, model, forBusiness)
    local cid = Framework.GetCitizenId(src)
    if not cid then return false, 'No character loaded.' end

    local entry = kind == 'trailer' and Util.ShopTrailer(model) or Util.ShopTruck(model)
    if not entry then return false, 'That is not for sale.' end

    local stats = Progress.Stats(cid, Framework.GetName(src))
    if entry.level and stats.level < entry.level then return false, ('You need level %d for that.'):format(entry.level) end

    local bizId
    if forBusiness then
        local can, biz = Business.Can(src, 'fleet')
        if not biz then return false, 'You are not in a business.' end
        if not can then return false, 'Your rank cannot buy business trucks.' end

        local _, fleetSlots = Business.Slots(biz)
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM xs_trucking_owned WHERE company_id = ?', { biz.id }) or 0
        if tonumber(count) >= fleetSlots then return false, 'The business fleet is full. Buy more truck slots.' end

        if not Business.Charge(src, biz, entry.price, 'purchase', entry.label) then
            return false, ('That costs %s and the business bank is short.'):format(Util.Money(entry.price))
        end
        bizId = biz.id
    elseif not Framework.RemoveMoney(src, Config.Payout.account, entry.price, 'XS-Trucking:buy') then
        return false, ('That costs %s.'):format(Util.Money(entry.price))
    end

    local id = MySQL.insert.await(
        "INSERT INTO xs_trucking_owned (citizenid, company_id, kind, model, label, trailer_type, `condition`) VALUES (?, NULLIF(?, 0), ?, ?, ?, NULLIF(?, ''), 100)",
        { cid, bizId or 0, kind == 'trailer' and 'trailer' or 'truck', entry.model, entry.label, kind == 'trailer' and entry.type or '' })
    Garage.Plate({ id = id })
    return true, id
end

function Garage.Sell(src, id)
    local row, cid, err = ownRow(src, id)
    if not row then return false, err end
    if row.dispatch_ready_at then return false, 'It is out on a fleet run.' end
    if Jobs.UsingOwned(row.id) then return false, 'It is out on a load right now.' end

    local shop = row.kind == 'truck' and Util.ShopTruck(row.model) or Util.ShopTrailer(row.model)
    local value = shop and math.floor(shop.price * (Config.Trucks.sellBack or 50) / 100) or 0

    if row.company_id then
        local can, biz = Business.Can(src, 'fleet')
        if not can then return false, 'Your rank cannot sell business trucks.' end
        MySQL.update.await('DELETE FROM xs_trucking_owned WHERE id = ?', { row.id })
        if value > 0 then Business.Credit(biz.id, value, 'sale', row.label) end
    else
        MySQL.update.await('DELETE FROM xs_trucking_owned WHERE id = ?', { row.id })
        if value > 0 then Framework.AddMoney(src, Config.Payout.account, value, 'XS-Trucking:sell') end
    end

    for _, pick in pairs(selected) do
        if pick.truck == row.id then pick.truck = nil end
        if pick.trailer == row.id then pick.trailer = nil end
    end
    return true, value
end

function Garage.Repair(src, id)
    local row, cid, err = ownRow(src, id)
    if not row then return false, err end
    if row.condition >= 100 then return false, 'The body is already perfect.' end

    local cost = discount(cid, 'repair', (100 - row.condition) * SGet('economy.bodyCost', Config.Parts.bodyCostPerPoint), row)
    local ok, why = pay(src, cid, row, cost, 'repair')
    if not ok then return false, why end

    MySQL.update.await('UPDATE xs_trucking_owned SET `condition` = 100 WHERE id = ?', { row.id })
    return true, cost
end

function Garage.Service(src, id, partId)
    local row, cid, err = ownRow(src, id)
    if not row then return false, err end
    if row.kind ~= 'truck' then return false, 'Only trucks need servicing.' end

    local parts = Garage.Parts(row)
    local cost = 0
    local list = partId == 'all' and Config.Parts.list or { PART_IDS[partId] }
    if not list[1] then return false, 'Unknown part.' end

    for _, part in ipairs(list) do
        cost = cost + part.cost * (100 - (parts[part.id] or 100)) / 100
    end
    cost = discount(cid, 'repair', math.ceil(cost), row)
    if cost <= 0 then return false, 'Nothing needs doing.' end

    local ok, why = pay(src, cid, row, cost, 'service')
    if not ok then return false, why end

    for _, part in ipairs(list) do parts[part.id] = 100 end
    saveParts(row.id, parts)
    return true, cost
end

function Garage.Refuel(src, id)
    local row, cid, err = ownRow(src, id)
    if not row then return false, err end
    if row.kind ~= 'truck' then return false, 'Trailers do not take fuel.' end

    local parts = Garage.Parts(row)
    local missing = 100 - (parts.fuel or 100)
    if missing < 1 then return false, 'The tank is full.' end

    local cost = math.ceil(missing * SGet('economy.fuelPrice', Config.DepotFuelPrice))
    local ok, why = pay(src, cid, row, cost, 'fuel')
    if not ok then return false, why end

    parts.fuel = 100
    saveParts(row.id, parts)
    return true, cost
end

local function upgradeDef(id)
    for _, def in ipairs(Config.Upgrades.performance) do
        if def.id == id then return def end
    end
    return nil
end

function Garage.Upgrade(src, id, upgradeId)
    local row, cid, err = ownRow(src, id)
    if not row then return false, err end
    if row.kind ~= 'truck' then return false, 'Only trucks take upgrades.' end

    local def = upgradeDef(upgradeId)
    if not def then return false, 'Unknown upgrade.' end

    local upgrades = Util.Decode(row.upgrades) or {}
    local level = tonumber(upgrades[upgradeId]) or 0
    if level >= def.levels then return false, 'Already maxed out.' end

    local cost = discount(cid, 'upgrade', def.cost * (level + 1))
    local ok, why = pay(src, cid, row, cost, 'upgrade')
    if not ok then return false, why end

    upgrades[upgradeId] = level + 1
    MySQL.update.await('UPDATE xs_trucking_owned SET upgrades = ? WHERE id = ?', { json.encode(upgrades), row.id })
    return true, cost
end

local function paletteHas(id)
    for _, colour in ipairs(Config.Upgrades.paint.colours) do
        if colour.id == id then return true end
    end
    return false
end

function Garage.Style(src, id, style)
    local row, cid, err = ownRow(src, id)
    if not row then return false, err end
    if row.kind ~= 'truck' then return false, 'Only trucks can be styled.' end
    if type(style) ~= 'table' then return false, 'Nothing to change.' end

    local livery = Util.Decode(row.livery) or {}
    local cost = 0

    local primary, secondary = tonumber(style.primary), tonumber(style.secondary)
    if primary and secondary and (primary ~= livery.primary or secondary ~= livery.secondary) then
        if not paletteHas(primary) or not paletteHas(secondary) then return false, 'That colour is not offered.' end
        livery.primary, livery.secondary = primary, secondary
        cost = cost + Config.Upgrades.paint.cost
    end

    if style.xenon ~= nil then
        local colour = style.xenon == false and false or math.floor(Util.Clamp(style.xenon, -1, 12))
        if colour ~= livery.xenon then
            livery.xenon = colour
            if colour ~= false then cost = cost + Config.Upgrades.lights.cost end
        end
    end

    if style.tint ~= nil then
        local tint = math.floor(Util.Clamp(style.tint, 0, 3))
        if tint ~= (livery.tint or 0) then
            livery.tint = tint
            if tint > 0 then cost = cost + Config.Upgrades.tint.cost end
        end
    end

    if style.horn ~= nil then
        local horn = math.floor(Util.Clamp(style.horn, -1, #Config.Upgrades.horns.list - 1))
        if horn ~= (livery.horn or -1) then
            livery.horn = horn
            if horn >= 0 then cost = cost + Config.Upgrades.horns.cost end
        end
    end

    if cost == 0 and not style.free then
        MySQL.update.await('UPDATE xs_trucking_owned SET livery = ? WHERE id = ?', { json.encode(livery), row.id })
        return true, 0
    end

    cost = discount(cid, 'upgrade', cost)
    local ok, why = pay(src, cid, row, cost, 'style')
    if not ok then return false, why end

    MySQL.update.await('UPDATE xs_trucking_owned SET livery = ? WHERE id = ?', { json.encode(livery), row.id })
    return true, cost
end

function Garage.Rename(src, id, nickname)
    local row, _, err = ownRow(src, id)
    if not row then return false, err end
    nickname = Util.Text(nickname, 32)
    MySQL.update.await("UPDATE xs_trucking_owned SET nickname = NULLIF(?, '') WHERE id = ?", { nickname, row.id })
    return true
end

function Garage.Reserve(src, id, targetCid)
    local row = Garage.Row(id)
    if not row or not row.company_id then return false, 'Only business trucks can be reserved.' end
    local can, biz = Business.Can(src, 'fleet')
    if not biz or biz.id ~= row.company_id then return false, 'That truck is not your business.' end
    if not can then return false, 'Your rank cannot assign trucks.' end
    if targetCid and targetCid ~= '' and not biz.members[targetCid] then return false, 'They are not a member.' end

    MySQL.update.await("UPDATE xs_trucking_owned SET reserved_for = NULLIF(?, '') WHERE id = ?", { targetCid or '', row.id })
    return true
end

function Garage.ApplyTrip(row, km, damage, cid, fuel)
    if not row then return end

    local parts = Garage.Parts(row)
    parts.odometer = (parts.odometer or 0) + km
    if fuel then parts.fuel = Util.Clamp(fuel, 0, 100) end

    if Config.Parts.enabled then
        local wear = 1 - math.min(Progress.Mod(cid, 'wear'), 80) / 100
        for _, part in ipairs(Config.Parts.list) do
            local loss = (km * part.perKm + math.max(0, damage) * part.perDamage) * wear
            parts[part.id] = Util.Round(Util.Clamp((parts[part.id] or 100) - loss, 0, 100), 1)
        end
    end
    saveParts(row.id, parts)

    local rate = Config.Parts.bodyLossPerDamage
    if (parts.brakes or 100) < Config.Parts.brakesDamageBelow then rate = rate * Config.Parts.brakesDamageMult end
    local loss = math.floor(math.max(0, damage) * rate)
    if loss > 0 then
        MySQL.update.await('UPDATE xs_trucking_owned SET `condition` = GREATEST(0, `condition` - ?) WHERE id = ?', { loss, row.id })
    end
end

function Garage.SendRun(src, id, routeId)
    if not Config.Business.runs.enabled then return false, 'Fleet runs are turned off.' end

    local row, cid, err = ownRow(src, id)
    if not row then return false, err end
    if row.kind ~= 'truck' then return false, 'Only trucks go on runs.' end
    if row.dispatch_ready_at then return false, 'It is already out.' end
    if row.condition <= 0 then return false, 'It needs repairing first.' end
    if Jobs.UsingOwned(row.id) then return false, 'It is out on a load right now.' end

    local route = Spots.Route(routeId)
    if not route or not route.enabled or route.illegal then return false, 'Pick a route for it.' end

    local biz = row.company_id and Business.Get(row.company_id)
    if biz then
        local can = Business.Can(src, 'fleet')
        if not can then return false, 'Your rank cannot send business trucks out.' end
    end

    local mods = Business.Mods(biz)
    local owner = row.company_id and 'company_id = ?' or 'citizenid = ? AND company_id IS NULL'
    local out = MySQL.scalar.await(('SELECT COUNT(*) FROM xs_trucking_owned WHERE %s AND dispatch_ready_at IS NOT NULL'):format(owner),
        { row.company_id or cid }) or 0
    if tonumber(out) >= Config.Business.runs.max + mods.runs then return false, 'Too many trucks are out already.' end

    local minutes = SGet('business.runMinutes', Config.Business.runs.minutes) * (1 - math.min(mods.runTime, 80) / 100)
    local payout = math.floor(route.pay * SGet('business.runPay', Config.Business.runs.payPercent) / 100)
    local readyAt = (os.time() + math.floor(minutes * 60)) * 1000

    MySQL.update.await('UPDATE xs_trucking_owned SET dispatch_ready_at = ?, dispatch_contract_id = ?, dispatch_payout = ? WHERE id = ?',
        { readyAt, tostring(route.id), payout, row.id })
    return true, math.floor(minutes)
end

function Garage.Collect(src, id)
    local row, cid, err = ownRow(src, id)
    if not row then return false, err end
    if not row.dispatch_ready_at then return false, 'It is not out on a run.' end
    if os.time() * 1000 < row.dispatch_ready_at then return false, 'It is not back yet.' end

    local payout = row.dispatch_payout or 0
    MySQL.update.await('UPDATE xs_trucking_owned SET dispatch_ready_at = NULL, dispatch_contract_id = NULL, dispatch_payout = NULL WHERE id = ?', { row.id })
    Garage.ApplyTrip(row, 8, 0, cid)

    if row.company_id then
        Business.Credit(row.company_id, payout, 'run', ('Fleet run by %s'):format(row.nickname or row.label))
        Business.AddRep(row.company_id, math.floor(Config.Business.repPerLoad / 2))
    else
        Framework.AddMoney(src, Config.Payout.account, payout, 'XS-Trucking:run')
    end
    return true, payout
end

AddEventHandler('playerDropped', function()
    selected[source] = nil
end)
