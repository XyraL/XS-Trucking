Business = {}

local cache = {}
local byCitizen = {}
local invites = {}

local LEGACY_PERMS = { manage_treasury = 'bank', manage_vehicles = 'fleet', manage_perks = 'perks' }

local function decodePerms(raw)
    if raw == '*' then return '*' end
    local list = Util.Decode(raw) or {}
    local out, seen = {}, {}
    for _, perm in ipairs(list) do
        perm = LEGACY_PERMS[perm] or perm
        if Config.Business.permissions[perm] and not seen[perm] then
            seen[perm] = true
            out[#out + 1] = perm
        end
    end
    return out
end

local function load(id)
    local row = MySQL.single.await('SELECT * FROM xs_trucking_companies WHERE id = ?', { id })
    if not row then return nil end

    row.ranks = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM xs_trucking_company_ranks WHERE company_id = ?', { id }) or {}) do
        row.ranks[r.grade] = { grade = r.grade, name = r.name, permissions = decodePerms(r.permissions), cut = r.cut or 60 }
    end

    row.members = {}
    for _, m in ipairs(MySQL.query.await('SELECT * FROM xs_trucking_company_members WHERE company_id = ?', { id }) or {}) do
        row.members[m.citizenid] = m
        byCitizen[m.citizenid] = id
    end

    row.perks = {}
    for _, p in ipairs(MySQL.query.await('SELECT perk_id FROM xs_trucking_company_perks WHERE company_id = ?', { id }) or {}) do
        row.perks[p.perk_id] = true
    end

    cache[id] = row
    return row
end

function Business.Get(id)
    id = tonumber(id)
    if not id then return nil end
    if cache[id] then return cache[id] end
    if not WaitForDB() then return nil end
    return load(id)
end

function Business.ByCitizen(cid)
    if not cid then return nil end
    local id = byCitizen[cid]
    if id == false then return nil end
    if id and cache[id] then return cache[id] end
    if not WaitForDB() then return nil end

    local row = MySQL.single.await('SELECT company_id FROM xs_trucking_company_members WHERE citizenid = ?', { cid })
    if not row then
        byCitizen[cid] = false
        return nil
    end
    return load(row.company_id)
end

function Business.BySource(src)
    return Business.ByCitizen(Framework.GetCitizenId(src))
end

local function topGrade(biz)
    local top = 0
    for grade in pairs(biz.ranks) do
        if grade > top then top = grade end
    end
    return top
end

local function gradeCan(biz, grade, perm)
    local rank = biz.ranks[grade]
    if not rank then return false end
    if rank.permissions == '*' then return true end
    for _, p in ipairs(rank.permissions) do
        if p == perm then return true end
    end
    return false
end

function Business.Can(src, perm)
    local cid = Framework.GetCitizenId(src)
    local biz = cid and Business.ByCitizen(cid)
    local member = biz and biz.members[cid]
    if not member then return false, biz end
    if biz.owner == cid then return true, biz end
    return gradeCan(biz, member.grade, perm), biz
end

function Business.Level(biz)
    local best = Config.Business.levels[1]
    for _, def in ipairs(Config.Business.levels) do
        if (biz.reputation or 0) >= def.rep then best = def end
    end
    return best
end

function Business.Mods(biz)
    local mods = { runs = 0, runTime = 0, pay = 0, deposit = 0, rep = 0, repair = 0 }
    if not biz then return mods end
    for _, branch in ipairs(Config.Business.perks) do
        for _, tier in ipairs(branch.tiers) do
            if biz.perks[tier.id] then
                for key in pairs(mods) do
                    if tier[key] then mods[key] = mods[key] + tier[key] end
                end
            end
        end
    end
    return mods
end

function Business.Slots(biz)
    local function total(def, tier)
        local n = def.base
        for i = 1, math.min(tier or 0, #def.upgrades) do n = n + def.upgrades[i].add end
        return n
    end
    return total(Config.Business.members, biz.member_tier), total(Config.Business.fleet, biz.fleet_tier)
end

function Business.CutFor(biz, cid)
    local member = biz and biz.members[cid]
    local rank = member and biz.ranks[member.grade]
    return rank and rank.cut or (Config.Business.ranks[1] and Config.Business.ranks[1].cut or 60)
end

local function ledger(bizId, src, kind, amount, note)
    MySQL.insert('INSERT INTO xs_trucking_company_ledger (company_id, citizenid, name, kind, amount, note) VALUES (?, ?, ?, ?, ?, ?)', {
        bizId, src and Framework.GetCitizenId(src) or '', src and Framework.GetName(src) or 'System', kind, math.floor(amount),
        Util.Text(note or '', 160),
    })
end

function Business.Credit(bizId, amount, kind, note)
    local biz = Business.Get(bizId)
    if not biz or amount == 0 then return end
    biz.bank = biz.bank + amount
    MySQL.update('UPDATE xs_trucking_companies SET bank = bank + ? WHERE id = ?', { amount, bizId })
    ledger(bizId, nil, kind or 'income', amount, note)
end

function Business.Charge(src, biz, amount, kind, note)
    if amount <= 0 then return true end
    if biz.bank < amount then return false end
    local changed = MySQL.update.await('UPDATE xs_trucking_companies SET bank = bank - ? WHERE id = ? AND bank >= ?', { amount, biz.id, amount })
    if (tonumber(changed) or 0) < 1 then return false end
    biz.bank = biz.bank - amount
    ledger(biz.id, src, kind or 'expense', -amount, note)
    return true
end

function Business.AddRep(bizId, amount)
    local biz = Business.Get(bizId)
    if not biz or amount <= 0 then return end

    local before = Business.Level(biz).level
    biz.reputation = (biz.reputation or 0) + amount
    local after = Business.Level(biz).level

    local points = 0
    if after > before then
        for _, def in ipairs(Config.Business.levels) do
            if def.level > before and def.level <= after then points = points + (def.points or 0) end
        end
    end

    biz.perk_points = (biz.perk_points or 0) + points
    MySQL.update('UPDATE xs_trucking_companies SET reputation = ?, perk_points = perk_points + ? WHERE id = ?',
        { biz.reputation, points, bizId })
end

function Business.CountDelivery(bizId, cid, amount)
    local biz = Business.Get(bizId)
    if not biz then return end
    biz.total_deliveries = (biz.total_deliveries or 0) + 1
    MySQL.update('UPDATE xs_trucking_companies SET total_deliveries = total_deliveries + 1 WHERE id = ?', { bizId })

    local member = biz.members[cid]
    if member then
        member.deliveries = (member.deliveries or 0) + 1
        member.earned = (member.earned or 0) + (amount or 0)
        MySQL.update('UPDATE xs_trucking_company_members SET deliveries = deliveries + 1, earned = earned + ?, last_seen = ? WHERE citizenid = ?',
            { amount or 0, os.time(), cid })
    end
end

local function validName(name)
    name = Util.Text(name, Config.Business.nameLength[2])
    if #name < Config.Business.nameLength[1] then
        return nil, ('Names are %d to %d characters.'):format(Config.Business.nameLength[1], Config.Business.nameLength[2])
    end
    return name
end

function Business.ValidLogo(url)
    url = Util.Trim(url)
    if url == '' then return '' end
    if #url > 255 then return nil, 'That link is too long.' end

    local host = url:match('^https://([%w%.%-]+)/')
    if not host then return nil, 'Use an https link to the picture.' end
    host = host:lower()

    for _, allowed in ipairs(Config.Business.logoHosts) do
        allowed = allowed:lower()
        if host == allowed or host:sub(-(#allowed + 1)) == '.' .. allowed then return url end
    end
    return nil, ('Logos have to be hosted on %s.'):format(table.concat(Config.Business.logoHosts, ' or '))
end

function Business.Found(src, name)
    if not Config.Business.enabled then return false, 'Businesses are turned off.' end

    local cid = Framework.GetCitizenId(src)
    if not cid then return false, 'No character loaded.' end
    if Business.ByCitizen(cid) then return false, 'You are already in a business.' end

    local clean, err = validName(name)
    if not clean then return false, err end
    if MySQL.scalar.await('SELECT 1 FROM xs_trucking_companies WHERE name = ?', { clean }) then
        return false, 'That name is taken.'
    end

    local cost = SGet('business.foundingCost', Config.Business.foundingCost)
    if not Framework.RemoveMoney(src, Config.Payout.account, cost, 'XS-Trucking:business') then
        return false, ('Starting a business costs %s.'):format(Util.Money(cost))
    end

    local id = MySQL.insert.await('INSERT INTO xs_trucking_companies (name, label, owner) VALUES (?, ?, ?)', { clean, clean, cid })

    for i, rank in ipairs(Config.Business.ranks) do
        local perms = rank.permissions == '*' and '*' or json.encode(rank.permissions)
        MySQL.insert.await('INSERT INTO xs_trucking_company_ranks (company_id, grade, name, permissions, cut) VALUES (?, ?, ?, ?, ?)',
            { id, i - 1, rank.name, perms, rank.cut })
    end

    MySQL.insert.await('INSERT INTO xs_trucking_company_members (company_id, citizenid, name, grade, last_seen) VALUES (?, ?, ?, ?, ?)',
        { id, cid, Framework.GetName(src), #Config.Business.ranks - 1, os.time() })

    byCitizen[cid] = id
    load(id)
    ledger(id, src, 'founded', 0, 'Business started')
    return true, id
end

function Business.Invite(src, target)
    local can, biz = Business.Can(src, 'invite')
    if not biz then return false, 'You are not in a business.' end
    if not can then return false, 'Your rank cannot invite players.' end

    target = tonumber(target)
    local targetCid = target and Framework.GetCitizenId(target)
    if not targetCid then return false, 'That player is not around.' end
    if Business.ByCitizen(targetCid) then return false, 'They are already in a business.' end

    local slots = Business.Slots(biz)
    local count = 0
    for _ in pairs(biz.members) do count = count + 1 end
    if count >= slots then return false, 'The business is full. Buy more member slots.' end

    invites[target] = { id = biz.id, from = Framework.GetName(src), expires = os.time() + 120 }
    TriggerClientEvent('XS-Trucking:client:businessInvite', target, { business = biz.label, from = invites[target].from, logo = biz.logo_hidden == 0 and biz.logo or '' })
    return true
end

function Business.Accept(src)
    local invite = invites[src]
    invites[src] = nil
    if not invite or invite.expires < os.time() then return false, 'That invite has run out.' end

    local cid = Framework.GetCitizenId(src)
    if not cid then return false, 'No character loaded.' end
    if Business.ByCitizen(cid) then return false, 'You are already in a business.' end

    local biz = Business.Get(invite.id)
    if not biz then return false, 'That business is gone.' end

    MySQL.insert.await('INSERT INTO xs_trucking_company_members (company_id, citizenid, name, grade, last_seen) VALUES (?, ?, ?, 0, ?)',
        { biz.id, cid, Framework.GetName(src), os.time() })
    byCitizen[cid] = biz.id
    load(biz.id)
    ledger(biz.id, src, 'joined', 0, 'Joined the business')
    return true, biz.label
end

function Business.Leave(src)
    local cid = Framework.GetCitizenId(src)
    local biz = cid and Business.ByCitizen(cid)
    if not biz then return false, 'You are not in a business.' end
    if biz.owner == cid then return false, 'Owners cannot leave. Hand it over or close the business.' end

    MySQL.update.await('DELETE FROM xs_trucking_company_members WHERE citizenid = ? AND company_id = ?', { cid, biz.id })
    MySQL.update('UPDATE xs_trucking_owned SET reserved_for = NULL WHERE company_id = ? AND reserved_for = ?', { biz.id, cid })
    biz.members[cid] = nil
    byCitizen[cid] = false
    ledger(biz.id, src, 'left', 0, 'Left the business')
    return true
end

function Business.Kick(src, targetCid)
    local can, biz = Business.Can(src, 'kick')
    if not biz then return false, 'You are not in a business.' end
    if not can then return false, 'Your rank cannot remove members.' end

    local member = biz.members[targetCid]
    if not member then return false, 'They are not a member.' end
    if biz.owner == targetCid then return false, 'The owner cannot be removed.' end

    local myGrade = biz.members[Framework.GetCitizenId(src)].grade
    if biz.owner ~= Framework.GetCitizenId(src) and member.grade >= myGrade then
        return false, 'You can only remove members below your rank.'
    end

    MySQL.update.await('DELETE FROM xs_trucking_company_members WHERE citizenid = ? AND company_id = ?', { targetCid, biz.id })
    MySQL.update('UPDATE xs_trucking_owned SET reserved_for = NULL WHERE company_id = ? AND reserved_for = ?', { biz.id, targetCid })
    biz.members[targetCid] = nil
    byCitizen[targetCid] = false
    ledger(biz.id, src, 'kicked', 0, ('Removed %s'):format(member.name))
    return true
end

function Business.SetGrade(src, targetCid, grade)
    local can, biz = Business.Can(src, 'promote')
    if not biz then return false, 'You are not in a business.' end
    if not can then return false, 'Your rank cannot change ranks.' end

    grade = tonumber(grade)
    local member = biz.members[targetCid]
    if not member then return false, 'They are not a member.' end
    if not grade or not biz.ranks[grade] then return false, 'That rank does not exist.' end
    if biz.owner == targetCid then return false, "The owner's rank cannot change." end

    local myCid = Framework.GetCitizenId(src)
    if biz.owner ~= myCid then
        local mine = biz.members[myCid].grade
        if grade >= mine or member.grade >= mine then return false, 'You can only move members below your own rank.' end
    end
    if grade >= topGrade(biz) and biz.owner ~= myCid then return false, 'Only the owner can hand out the top rank.' end

    MySQL.update.await('UPDATE xs_trucking_company_members SET grade = ? WHERE citizenid = ? AND company_id = ?', { grade, targetCid, biz.id })
    member.grade = grade
    ledger(biz.id, src, 'rank', 0, ('%s is now %s'):format(member.name, biz.ranks[grade].name))
    return true
end

function Business.SaveRanks(src, ranks)
    local can, biz = Business.Can(src, 'ranks')
    if not biz then return false, 'You are not in a business.' end
    if not can then return false, 'Your rank cannot edit ranks.' end
    if type(ranks) ~= 'table' or #ranks < 2 then return false, 'A business needs at least two ranks.' end
    if #ranks > Config.Business.maxRanks then return false, ('At most %d ranks.'):format(Config.Business.maxRanks) end

    local clean = {}
    for i, rank in ipairs(ranks) do
        local name = Util.Text(rank.name, 32)
        if #name < 1 then return false, 'Every rank needs a name.' end

        local perms = {}
        if i == #ranks then
            perms = '*'
        else
            for _, perm in ipairs(type(rank.permissions) == 'table' and rank.permissions or {}) do
                if Config.Business.permissions[perm] then perms[#perms + 1] = perm end
            end
        end
        clean[i] = { grade = i - 1, name = name, cut = math.floor(Util.Clamp(rank.cut, 0, 100)), permissions = perms }
    end

    local top = #clean - 1
    for cid, member in pairs(biz.members) do
        if member.grade > top or (cid == biz.owner and member.grade ~= top) then
            local grade = cid == biz.owner and top or math.min(member.grade, top - 1)
            MySQL.update.await('UPDATE xs_trucking_company_members SET grade = ? WHERE citizenid = ?', { grade, cid })
            member.grade = grade
        end
    end

    MySQL.update.await('DELETE FROM xs_trucking_company_ranks WHERE company_id = ?', { biz.id })
    biz.ranks = {}
    for _, rank in ipairs(clean) do
        MySQL.insert.await('INSERT INTO xs_trucking_company_ranks (company_id, grade, name, permissions, cut) VALUES (?, ?, ?, ?, ?)',
            { biz.id, rank.grade, rank.name, rank.permissions == '*' and '*' or json.encode(rank.permissions), rank.cut })
        biz.ranks[rank.grade] = rank
    end

    ledger(biz.id, src, 'ranks', 0, 'Ranks updated')
    return true
end

function Business.SaveProfile(src, data)
    local can, biz = Business.Can(src, 'settings')
    if not biz then return false, 'You are not in a business.' end
    if not can then return false, 'Your rank cannot change the business settings.' end
    if type(data) ~= 'table' then return false, 'Nothing to save.' end

    local logo, err = Business.ValidLogo(data.logo or '')
    if not logo then return false, err end

    local colour = tostring(data.colour or biz.colour or '#38d9ff')
    if not colour:match('^#%x%x%x%x%x%x$') then colour = biz.colour or '#38d9ff' end

    local label = biz.label
    if data.name and Util.Text(data.name, 64) ~= biz.label then
        local clean, nameErr = validName(data.name)
        if not clean then return false, nameErr end
        if MySQL.scalar.await('SELECT 1 FROM xs_trucking_companies WHERE name = ? AND id <> ?', { clean, biz.id }) then
            return false, 'That name is taken.'
        end
        label = clean
    end

    local motto = Util.Text(data.motto or '', 120)
    local recruiting = data.recruiting ~= false

    local logoChanged = logo ~= biz.logo
    MySQL.update.await('UPDATE xs_trucking_companies SET name = ?, label = ?, logo = ?, logo_hidden = ?, colour = ?, motto = ?, recruiting = ? WHERE id = ?', {
        label, label, logo, logoChanged and 0 or biz.logo_hidden, colour, motto, recruiting and 1 or 0, biz.id,
    })

    biz.name, biz.label, biz.logo, biz.colour, biz.motto = label, label, logo, colour, motto
    biz.recruiting = recruiting and 1 or 0
    if logoChanged then biz.logo_hidden = 0 end
    ledger(biz.id, src, 'settings', 0, logoChanged and 'Logo changed' or 'Settings changed')
    return true
end

function Business.Deposit(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Enter an amount.' end

    local biz = Business.BySource(src)
    if not biz then return false, 'You are not in a business.' end
    if not Framework.RemoveMoney(src, Config.Payout.account, amount, 'XS-Trucking:deposit') then
        return false, 'You do not have that much.'
    end

    local credited = amount + math.floor(amount * Business.Mods(biz).deposit / 100)
    biz.bank = biz.bank + credited
    MySQL.update.await('UPDATE xs_trucking_companies SET bank = bank + ? WHERE id = ?', { credited, biz.id })
    ledger(biz.id, src, 'deposit', credited, credited > amount and ('Includes %s bonus'):format(Util.Money(credited - amount)) or nil)
    return true, biz.bank
end

function Business.Withdraw(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Enter an amount.' end

    local can, biz = Business.Can(src, 'bank')
    if not biz then return false, 'You are not in a business.' end
    if not can then return false, 'Your rank cannot withdraw.' end
    if not Business.Charge(src, biz, amount, 'withdraw') then return false, 'The bank does not have that much.' end

    Framework.AddMoney(src, Config.Payout.account, amount, 'XS-Trucking:withdraw')
    return true, biz.bank
end

function Business.BuyPerk(src, perkId)
    local can, biz = Business.Can(src, 'perks')
    if not biz then return false, 'You are not in a business.' end
    if not can then return false, 'Your rank cannot spend perk points.' end
    if biz.perks[perkId] then return false, 'Already unlocked.' end

    for _, branch in ipairs(Config.Business.perks) do
        for i, tier in ipairs(branch.tiers) do
            if tier.id == perkId then
                if i > 1 and not biz.perks[branch.tiers[i - 1].id] then
                    return false, ('Unlock %s first.'):format(branch.tiers[i - 1].label)
                end
                if (biz.perk_points or 0) < tier.cost then return false, 'Not enough perk points.' end

                biz.perk_points = biz.perk_points - tier.cost
                biz.perks[perkId] = true
                MySQL.update.await('UPDATE xs_trucking_companies SET perk_points = perk_points - ? WHERE id = ?', { tier.cost, biz.id })
                MySQL.insert.await('INSERT IGNORE INTO xs_trucking_company_perks (company_id, perk_id) VALUES (?, ?)', { biz.id, perkId })
                ledger(biz.id, src, 'perk', 0, ('Unlocked %s'):format(tier.label))
                return true
            end
        end
    end
    return false, 'That perk does not exist.'
end

function Business.BuySlots(src, which)
    local can, biz = Business.Can(src, 'perks')
    if not biz then return false, 'You are not in a business.' end
    if not can then return false, 'Your rank cannot buy upgrades.' end

    local def = which == 'members' and Config.Business.members or which == 'fleet' and Config.Business.fleet or nil
    if not def then return false, 'Unknown upgrade.' end

    local column = which == 'members' and 'member_tier' or 'fleet_tier'
    local tier = (biz[column] or 0) + 1
    local step = def.upgrades[tier]
    if not step then return false, 'Already fully upgraded.' end
    if not Business.Charge(src, biz, step.cost, 'upgrade', ('%d more %s slots'):format(step.add, which == 'members' and 'member' or 'truck')) then
        return false, ('That costs %s from the business bank.'):format(Util.Money(step.cost))
    end

    biz[column] = tier
    MySQL.update.await(('UPDATE xs_trucking_companies SET `%s` = ? WHERE id = ?'):format(column), { tier, biz.id })
    return true
end

function Business.TransferOwner(src, targetCid)
    local cid = Framework.GetCitizenId(src)
    local biz = cid and Business.ByCitizen(cid)
    if not biz or biz.owner ~= cid then return false, 'Only the owner can hand the business over.' end
    local member = biz.members[targetCid]
    if not member then return false, 'They are not a member.' end

    local top = topGrade(biz)
    MySQL.update.await('UPDATE xs_trucking_companies SET owner = ? WHERE id = ?', { targetCid, biz.id })
    MySQL.update.await('UPDATE xs_trucking_company_members SET grade = ? WHERE citizenid = ?', { top, targetCid })
    MySQL.update.await('UPDATE xs_trucking_company_members SET grade = ? WHERE citizenid = ?', { math.max(0, top - 1), cid })
    biz.owner = targetCid
    member.grade = top
    biz.members[cid].grade = math.max(0, top - 1)
    ledger(biz.id, src, 'owner', 0, ('Handed to %s'):format(member.name))
    return true
end

function Business.DisbandById(id)
    id = tonumber(id)
    MySQL.update.await('UPDATE xs_trucking_owned SET company_id = NULL, reserved_for = NULL WHERE company_id = ?', { id })
    MySQL.update.await('DELETE FROM xs_trucking_companies WHERE id = ?', { id })
    for cid, bizId in pairs(byCitizen) do
        if bizId == id then byCitizen[cid] = false end
    end
    cache[id] = nil
end

function Business.Disband(src)
    local cid = Framework.GetCitizenId(src)
    local biz = cid and Business.ByCitizen(cid)
    if not biz then return false, 'You are not in a business.' end
    if biz.owner ~= cid then return false, 'Only the owner can close the business.' end
    Business.DisbandById(biz.id)
    return true
end

function Business.Ledger(bizId, limit)
    local rows = MySQL.query.await(
        'SELECT name, kind, amount, note, UNIX_TIMESTAMP(created_at) AS ts FROM xs_trucking_company_ledger WHERE company_id = ? ORDER BY id DESC LIMIT ?',
        { bizId, limit or Config.Business.ledgerLimit }) or {}
    for _, row in ipairs(rows) do
        row.amount = tonumber(row.amount) or 0
        row.ts = tonumber(row.ts) or 0
    end
    return rows
end

function Business.Public(biz)
    if not biz then return nil end
    return {
        id = biz.id,
        name = biz.label,
        logo = biz.logo_hidden == 0 and biz.logo or '',
        colour = biz.colour or '#38d9ff',
        motto = biz.motto or '',
    }
end

function Business.Invalidate(id)
    if id then cache[tonumber(id)] = nil end
end

function Business.SetLogoHidden(id, hidden)
    MySQL.update.await('UPDATE xs_trucking_companies SET logo_hidden = ? WHERE id = ?', { hidden and 1 or 0, id })
    local biz = cache[tonumber(id)]
    if biz then biz.logo_hidden = hidden and 1 or 0 end
end

function Business.TopGrade(biz)
    return topGrade(biz)
end

AddEventHandler('playerDropped', function()
    invites[source] = nil
end)
