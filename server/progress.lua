Progress = {}

local SKILLS = {}
for _, branch in ipairs(Config.Skills.branches) do
    for _, skill in ipairs(branch.skills) do
        skill.branch = branch.id
        SKILLS[skill.id] = skill
    end
end

local skillCache = {}
local certCache = {}

local function blankStats(cid, name)
    return { citizenid = cid, name = name or '', xp = 0, level = 1, total_completed = 0, total_earned = 0,
             rating_sum = 0, heat = 0, heat_at = 0, illegal_runs = 0 }
end

function Progress.Stats(cid, name)
    if not cid or not WaitForDB() then return blankStats(cid, name) end

    local row = MySQL.single.await('SELECT * FROM xs_trucking_stats WHERE citizenid = ?', { cid })
    if not row then
        MySQL.insert.await('INSERT IGNORE INTO xs_trucking_stats (citizenid, name) VALUES (?, ?)', { cid, name or '' })
        return blankStats(cid, name)
    end

    local level = Util.LevelForXp(row.xp)
    if level ~= row.level then
        row.level = level
        MySQL.update('UPDATE xs_trucking_stats SET level = ? WHERE citizenid = ?', { level, cid })
    end
    return row
end

function Progress.Rating(stats)
    if not stats or (stats.total_completed or 0) <= 0 then return 100 end
    return math.floor((stats.rating_sum or 0) / stats.total_completed)
end

function Progress.Skills(cid)
    if not cid then return {} end
    if skillCache[cid] then return skillCache[cid] end

    local ranks = {}
    for _, row in ipairs(MySQL.query.await('SELECT skill, `rank` FROM xs_trucking_skills WHERE citizenid = ?', { cid }) or {}) do
        if SKILLS[row.skill] then ranks[row.skill] = row.rank end
    end
    skillCache[cid] = ranks
    return ranks
end

function Progress.Points(stats, ranks)
    local earned = math.max(0, (stats.level or 1) - 1) * (Config.Levels.skillPointsPerLevel or 1)
    local spent = 0
    for _, rank in pairs(ranks or {}) do spent = spent + rank end
    return earned, spent, math.max(0, earned - spent)
end

local function matches(when, ctx)
    if not when then return true end
    if when.minKm and (ctx.km or 0) < when.minKm then return false end
    if when.minWeight and (ctx.weight or 0) < when.minWeight then return false end
    if when.night and not ctx.night then return false end
    if when.illegal ~= nil and (ctx.illegal == true) ~= when.illegal then return false end
    if when.business ~= nil and (ctx.business == true) ~= when.business then return false end
    if when.minRating and (ctx.rating or 0) < when.minRating then return false end
    if when.types then
        local ok = false
        for _, t in ipairs(when.types) do
            if t == ctx.type then ok = true break end
        end
        if not ok then return false end
    end
    return true
end

function Progress.Mods(cid, ctx)
    local mods = {}
    ctx = ctx or {}
    for skillId, rank in pairs(Progress.Skills(cid)) do
        local skill = SKILLS[skillId]
        for _, effect in ipairs(skill and skill.effects or {}) do
            if matches(effect.when, ctx) then
                mods[effect.stat] = (mods[effect.stat] or 0) + effect.value * rank
            end
        end
    end
    return mods
end

function Progress.Mod(cid, stat, ctx)
    return Progress.Mods(cid, ctx)[stat] or 0
end

function Progress.BuySkill(src, skillId)
    local cid = Framework.GetCitizenId(src)
    if not cid then return false, 'No character loaded.' end

    local skill = SKILLS[skillId]
    if not skill then return false, 'That skill does not exist.' end

    local stats = Progress.Stats(cid, Framework.GetName(src))
    local ranks = Progress.Skills(cid)
    local current = ranks[skillId] or 0
    if current >= skill.ranks then return false, 'That skill is maxed out.' end

    for _, need in ipairs(skill.requires or {}) do
        if (ranks[need] or 0) < 1 then
            return false, ('Needs %s first.'):format(SKILLS[need] and SKILLS[need].label or need)
        end
    end

    local _, _, available = Progress.Points(stats, ranks)
    if available < 1 then return false, 'No skill points left. Level up to earn more.' end

    MySQL.query.await('INSERT INTO xs_trucking_skills (citizenid, skill, `rank`) VALUES (?, ?, 1) ON DUPLICATE KEY UPDATE `rank` = `rank` + 1',
        { cid, skillId })
    ranks[skillId] = current + 1
    return true, current + 1
end

function Progress.Respec(src)
    local cid = Framework.GetCitizenId(src)
    if not cid then return false, 'No character loaded.' end

    local ranks = Progress.Skills(cid)
    if next(ranks) == nil then return false, 'You have no skills to reset.' end

    local cost = Config.Skills.respecCost or 0
    if cost > 0 and not Framework.RemoveMoney(src, Config.Payout.account, cost, 'XS-Trucking:respec') then
        return false, ('Resetting your skills costs %s.'):format(Util.Money(cost))
    end

    MySQL.update.await('DELETE FROM xs_trucking_skills WHERE citizenid = ?', { cid })
    skillCache[cid] = {}
    return true
end

function Progress.ResetSkills(cid)
    MySQL.update.await('DELETE FROM xs_trucking_skills WHERE citizenid = ?', { cid })
    skillCache[cid] = {}
end

function Progress.Certs(cid)
    if not cid then return {} end
    if certCache[cid] then return certCache[cid] end

    local certs = {}
    for _, row in ipairs(MySQL.query.await('SELECT cert FROM xs_trucking_certs WHERE citizenid = ?', { cid }) or {}) do
        certs[row.cert] = true
    end
    certCache[cid] = certs
    return certs
end

function Progress.HasCert(cid, cert)
    if not cert then return true end
    return Progress.Certs(cid)[cert] == true
end

function Progress.EarnCert(src, certId)
    local cid = Framework.GetCitizenId(src)
    if not cid then return false, 'No character loaded.' end

    local cert = Util.Certificate(certId)
    if not cert then return false, 'That certificate does not exist.' end
    if Progress.HasCert(cid, certId) then return false, 'You already hold it.' end

    local stats = Progress.Stats(cid, Framework.GetName(src))
    if stats.level < cert.level then return false, ('You need level %d.'):format(cert.level) end
    if (stats.total_completed or 0) < (cert.deliveries or 0) then
        return false, ('You need %d deliveries.'):format(cert.deliveries)
    end

    if (cert.fee or 0) > 0 and not Framework.RemoveMoney(src, Config.Payout.account, cert.fee, 'XS-Trucking:certificate') then
        return false, ('The certificate costs %s.'):format(Util.Money(cert.fee))
    end

    MySQL.insert.await('INSERT IGNORE INTO xs_trucking_certs (citizenid, cert) VALUES (?, ?)', { cid, certId })
    Progress.Certs(cid)[certId] = true
    return true
end

function Progress.GrantCert(cid, certId, grant)
    if grant then
        MySQL.insert.await('INSERT IGNORE INTO xs_trucking_certs (citizenid, cert) VALUES (?, ?)', { cid, certId })
    else
        MySQL.update.await('DELETE FROM xs_trucking_certs WHERE citizenid = ? AND cert = ?', { cid, certId })
    end
    certCache[cid] = nil
end

function Progress.Heat(stats)
    local heat = tonumber(stats.heat) or 0
    if heat <= 0 then return 0 end

    local hours = math.max(0, os.time() - (tonumber(stats.heat_at) or 0)) / 3600
    local decay = SGet('illegal.decayPerHour', Config.Illegal.decayPerHour)
    decay = decay * (1 + Progress.Mod(stats.citizenid, 'heatDecay') / 100)
    return math.max(0, math.floor(heat - hours * decay))
end

function Progress.AddHeat(cid, amount)
    local stats = Progress.Stats(cid)
    local heat = math.min(Config.Illegal.maxHeat, Progress.Heat(stats) + amount)
    MySQL.update.await('UPDATE xs_trucking_stats SET heat = ?, heat_at = ?, illegal_runs = illegal_runs + 1 WHERE citizenid = ?',
        { heat, os.time(), cid })
    return heat
end

function Progress.SetHeat(cid, heat)
    MySQL.update.await('UPDATE xs_trucking_stats SET heat = ?, heat_at = ? WHERE citizenid = ?',
        { math.floor(Util.Clamp(heat, 0, Config.Illegal.maxHeat)), os.time(), cid })
end

function Progress.Profile(src)
    local cid = Framework.GetCitizenId(src)
    if not cid then return nil end

    local stats = Progress.Stats(cid, Framework.GetName(src))
    local ranks = Progress.Skills(cid)
    local earned, spent, available = Progress.Points(stats, ranks)
    local level = stats.level

    return {
        name = Framework.GetName(src),
        level = level,
        title = Util.LevelTitle(level),
        xp = stats.xp,
        levelXp = Util.XpForLevel(level),
        nextXp = level < Config.Levels.max and Util.XpForLevel(level + 1) or nil,
        maxLevel = Config.Levels.max,
        deliveries = stats.total_completed,
        earned = stats.total_earned,
        rating = Progress.Rating(stats),
        heat = Progress.Heat(stats),
        illegalRuns = stats.illegal_runs or 0,
        skills = ranks,
        points = { earned = earned, spent = spent, available = available },
        certs = Progress.Certs(cid),
    }
end

function Progress.Forget(cid)
    skillCache[cid] = nil
    certCache[cid] = nil
end

function Progress.SkillInfo(skillId)
    return SKILLS[skillId]
end
