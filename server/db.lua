do
    local _register = lib.callback.register

    lib.callback.register = function(name, fn)
        return _register(name, function(src, ...)
            local results = { pcall(fn, src, ...) }

            if not results[1] then
                print(('^1[XS-Trucking]^0 callback "%s" errored: %s'):format(name, tostring(results[2])))
                return nil
            end

            return table.unpack(results, 2)
        end)
    end
end

DB = { ready = false, failed = false }

local TABLES = {
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_stats` (
            `citizenid` VARCHAR(64) NOT NULL,
            `name` VARCHAR(96) NOT NULL DEFAULT '',
            `xp` INT NOT NULL DEFAULT 0,
            `level` INT NOT NULL DEFAULT 1,
            `total_completed` INT NOT NULL DEFAULT 0,
            `total_earned` INT NOT NULL DEFAULT 0,
            `rating_sum` INT NOT NULL DEFAULT 0,
            `heat` INT NOT NULL DEFAULT 0,
            `heat_at` INT NOT NULL DEFAULT 0,
            `illegal_runs` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_companies` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(64) NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            `owner` VARCHAR(64) NOT NULL,
            `bank` BIGINT NOT NULL DEFAULT 0,
            `reputation` INT NOT NULL DEFAULT 0,
            `perk_points` INT NOT NULL DEFAULT 0,
            `total_deliveries` INT NOT NULL DEFAULT 0,
            `logo` VARCHAR(255) NOT NULL DEFAULT '',
            `logo_hidden` TINYINT NOT NULL DEFAULT 0,
            `colour` VARCHAR(9) NOT NULL DEFAULT '#38d9ff',
            `motto` VARCHAR(120) NOT NULL DEFAULT '',
            `recruiting` TINYINT NOT NULL DEFAULT 1,
            `member_tier` INT NOT NULL DEFAULT 0,
            `fleet_tier` INT NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `idx_name` (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_owned` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(64) NOT NULL,
            `company_id` INT UNSIGNED NULL,
            `kind` VARCHAR(16) NOT NULL DEFAULT 'truck',
            `model` VARCHAR(64) NOT NULL,
            `label` VARCHAR(96) NOT NULL DEFAULT '',
            `trailer_type` VARCHAR(16) NULL,
            `plate` VARCHAR(12) NULL,
            `nickname` VARCHAR(40) NULL,
            `reserved_for` VARCHAR(64) NULL,
            `condition` TINYINT NOT NULL DEFAULT 100,
            `dispatch_ready_at` BIGINT NULL,
            `dispatch_contract_id` VARCHAR(64) NULL,
            `dispatch_payout` INT NULL,
            `upgrades` LONGTEXT NULL,
            `livery` LONGTEXT NULL,
            `maintenance` LONGTEXT NULL,
            `purchased_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_citizen` (`citizenid`),
            KEY `idx_company` (`company_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_deliveries` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(64) NOT NULL,
            `contract_id` VARCHAR(64) NOT NULL,
            `label` VARCHAR(128) NOT NULL DEFAULT '',
            `cargo_type` VARCHAR(32) NOT NULL DEFAULT '',
            `base_payout` INT NOT NULL DEFAULT 0,
            `final_payout` INT NOT NULL DEFAULT 0,
            `driver_cut` INT NOT NULL DEFAULT 0,
            `company_cut` INT NOT NULL DEFAULT 0,
            `company_id` INT UNSIGNED NULL,
            `truck_bonus_pct` INT NOT NULL DEFAULT 0,
            `hot_bonus_pct` INT NOT NULL DEFAULT 0,
            `multistop_bonus_pct` INT NOT NULL DEFAULT 0,
            `rating_bonus_pct` INT NOT NULL DEFAULT 0,
            `skill_bonus_pct` INT NOT NULL DEFAULT 0,
            `coop_bonus_pct` INT NOT NULL DEFAULT 0,
            `spoiled` TINYINT NOT NULL DEFAULT 0,
            `trip_rating` INT NOT NULL DEFAULT 100,
            `stop_count` INT NOT NULL DEFAULT 1,
            `xp` INT NOT NULL DEFAULT 0,
            `distance_m` INT NOT NULL DEFAULT 0,
            `duration_seconds` INT NOT NULL DEFAULT 0,
            `spot_id` INT UNSIGNED NULL,
            `route_id` INT UNSIGNED NULL,
            `role` VARCHAR(12) NOT NULL DEFAULT 'driver',
            `illegal` TINYINT NOT NULL DEFAULT 0,
            `completed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_citizen` (`citizenid`),
            KEY `idx_citizen_time` (`citizenid`, `completed_at`),
            KEY `idx_company_time` (`company_id`, `completed_at`),
            KEY `idx_time` (`completed_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_settings` (
            `key` VARCHAR(64) NOT NULL,
            `value` TEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_company_ranks` (
            `company_id` INT UNSIGNED NOT NULL,
            `grade` INT NOT NULL,
            `name` VARCHAR(48) NOT NULL,
            `permissions` LONGTEXT NOT NULL,
            `cut` INT NOT NULL DEFAULT 60,
            PRIMARY KEY (`company_id`, `grade`),
            CONSTRAINT `fk_company_ranks_company` FOREIGN KEY (`company_id`)
                REFERENCES `xs_trucking_companies` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_company_members` (
            `company_id` INT UNSIGNED NOT NULL,
            `citizenid` VARCHAR(64) NOT NULL,
            `name` VARCHAR(96) NOT NULL DEFAULT '',
            `grade` INT NOT NULL DEFAULT 0,
            `deliveries` INT NOT NULL DEFAULT 0,
            `earned` BIGINT NOT NULL DEFAULT 0,
            `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `last_seen` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`),
            KEY `idx_company` (`company_id`),
            CONSTRAINT `fk_company_members_company` FOREIGN KEY (`company_id`)
                REFERENCES `xs_trucking_companies` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_company_perks` (
            `company_id` INT UNSIGNED NOT NULL,
            `perk_id` VARCHAR(48) NOT NULL,
            `bought_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`company_id`, `perk_id`),
            CONSTRAINT `fk_company_perks_company` FOREIGN KEY (`company_id`)
                REFERENCES `xs_trucking_companies` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_company_ledger` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `company_id` INT UNSIGNED NOT NULL,
            `citizenid` VARCHAR(64) NOT NULL DEFAULT '',
            `name` VARCHAR(96) NOT NULL DEFAULT '',
            `kind` VARCHAR(16) NOT NULL,
            `amount` BIGINT NOT NULL,
            `note` VARCHAR(160) NOT NULL DEFAULT '',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_company` (`company_id`),
            CONSTRAINT `fk_company_ledger_company` FOREIGN KEY (`company_id`)
                REFERENCES `xs_trucking_companies` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_spots` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(64) NOT NULL,
            `data` LONGTEXT NULL,
            `enabled` TINYINT NOT NULL DEFAULT 1,
            `created_by` VARCHAR(64) NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_routes` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `spot_id` INT UNSIGNED NOT NULL DEFAULT 0,
            `label` VARCHAR(64) NOT NULL,
            `data` LONGTEXT NULL,
            `enabled` TINYINT NOT NULL DEFAULT 1,
            `created_by` VARCHAR(64) NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_spot` (`spot_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_skills` (
            `citizenid` VARCHAR(64) NOT NULL,
            `skill` VARCHAR(48) NOT NULL,
            `rank` INT NOT NULL DEFAULT 1,
            PRIMARY KEY (`citizenid`, `skill`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_certs` (
            `citizenid` VARCHAR(64) NOT NULL,
            `cert` VARCHAR(48) NOT NULL,
            `earned_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`citizenid`, `cert`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `xs_trucking_admin_log` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(64) NOT NULL DEFAULT '',
            `name` VARCHAR(96) NOT NULL DEFAULT '',
            `action` VARCHAR(48) NOT NULL,
            `detail` VARCHAR(255) NOT NULL DEFAULT '',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
}

local COLUMNS = {
    { 'xs_trucking_stats', 'rating_sum', 'INT NOT NULL DEFAULT 0' },
    { 'xs_trucking_stats', 'heat', 'INT NOT NULL DEFAULT 0' },
    { 'xs_trucking_stats', 'heat_at', 'INT NOT NULL DEFAULT 0' },
    { 'xs_trucking_stats', 'illegal_runs', 'INT NOT NULL DEFAULT 0' },

    { 'xs_trucking_owned', 'company_id', 'INT UNSIGNED NULL' },
    { 'xs_trucking_owned', 'kind', "VARCHAR(16) NOT NULL DEFAULT 'truck'" },
    { 'xs_trucking_owned', 'trailer_type', 'VARCHAR(16) NULL' },
    { 'xs_trucking_owned', 'plate', 'VARCHAR(12) NULL' },
    { 'xs_trucking_owned', 'nickname', 'VARCHAR(40) NULL' },
    { 'xs_trucking_owned', 'reserved_for', 'VARCHAR(64) NULL' },
    { 'xs_trucking_owned', 'dispatch_ready_at', 'BIGINT NULL' },
    { 'xs_trucking_owned', 'dispatch_contract_id', 'VARCHAR(64) NULL' },
    { 'xs_trucking_owned', 'dispatch_payout', 'INT NULL' },
    { 'xs_trucking_owned', 'upgrades', 'LONGTEXT NULL' },
    { 'xs_trucking_owned', 'livery', 'LONGTEXT NULL' },
    { 'xs_trucking_owned', 'maintenance', 'LONGTEXT NULL' },

    { 'xs_trucking_companies', 'perk_points', 'INT NOT NULL DEFAULT 0' },
    { 'xs_trucking_companies', 'total_deliveries', 'INT NOT NULL DEFAULT 0' },
    { 'xs_trucking_companies', 'logo', "VARCHAR(255) NOT NULL DEFAULT ''" },
    { 'xs_trucking_companies', 'logo_hidden', 'TINYINT NOT NULL DEFAULT 0' },
    { 'xs_trucking_companies', 'colour', "VARCHAR(9) NOT NULL DEFAULT '#38d9ff'" },
    { 'xs_trucking_companies', 'motto', "VARCHAR(120) NOT NULL DEFAULT ''" },
    { 'xs_trucking_companies', 'recruiting', 'TINYINT NOT NULL DEFAULT 1' },
    { 'xs_trucking_companies', 'member_tier', 'INT NOT NULL DEFAULT 0' },
    { 'xs_trucking_companies', 'fleet_tier', 'INT NOT NULL DEFAULT 0' },

    { 'xs_trucking_company_ranks', 'cut', 'INT NOT NULL DEFAULT 60', after = function()
        MySQL.update.await("UPDATE `xs_trucking_company_ranks` SET `cut` = 85 WHERE `permissions` = '*'")
    end },
    { 'xs_trucking_company_members', 'deliveries', 'INT NOT NULL DEFAULT 0' },
    { 'xs_trucking_company_members', 'earned', 'BIGINT NOT NULL DEFAULT 0' },
    { 'xs_trucking_company_ledger', 'note', "VARCHAR(160) NOT NULL DEFAULT ''" },

    { 'xs_trucking_deliveries', 'skill_bonus_pct', 'INT NOT NULL DEFAULT 0' },
    { 'xs_trucking_deliveries', 'coop_bonus_pct', 'INT NOT NULL DEFAULT 0' },
    { 'xs_trucking_deliveries', 'spot_id', 'INT UNSIGNED NULL' },
    { 'xs_trucking_deliveries', 'route_id', 'INT UNSIGNED NULL' },
    { 'xs_trucking_deliveries', 'role', "VARCHAR(12) NOT NULL DEFAULT 'driver'" },
    { 'xs_trucking_deliveries', 'illegal', 'TINYINT NOT NULL DEFAULT 0' },
}

local function columnExists(tableName, column)
    local ok, rows = pcall(MySQL.query.await, ('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName), { column })
    if not ok or type(rows) ~= 'table' then return nil end
    return #rows > 0
end

local LEGACY_TRAILERS = {
    trailers4 = { type = 'reefer', model = 'trailers2' },
    tr2 = { type = 'flatbed', model = 'trflat' },
}

local function migrateTrailers()
    local rows = MySQL.query.await("SELECT `id`, `model` FROM `xs_trucking_owned` WHERE `kind` = 'trailer' AND `trailer_type` IS NULL") or {}
    for _, row in ipairs(rows) do
        local legacy = LEGACY_TRAILERS[row.model]
        local shop = Util.ShopTrailer(row.model)
        local kind = legacy and legacy.type or (shop and shop.type) or 'dryvan'
        MySQL.update.await('UPDATE `xs_trucking_owned` SET `trailer_type` = ?, `model` = ? WHERE `id` = ?',
            { kind, legacy and legacy.model or row.model, row.id })
    end
    return #rows
end

function DB.Install()
    local waited = 0
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(200)
        waited = waited + 200
        if waited >= 30000 then
            print('^1[XS-Trucking]^0 oxmysql never started. Check the ensure order in server.cfg.')
            return false
        end
    end

    local connected = false
    for _ = 1, 25 do
        if pcall(MySQL.scalar.await, 'SELECT 1') then connected = true break end
        Wait(400)
    end
    if not connected then
        print('^1[XS-Trucking]^0 could not reach the database.')
        return false
    end

    for _, statement in ipairs(TABLES) do
        local ok, err = pcall(MySQL.query.await, statement)
        if not ok then
            print(('^1[XS-Trucking]^0 could not create a table: %s'):format(tostring(err)))
            return false
        end
    end

    for _, entry in ipairs(COLUMNS) do
        local exists = columnExists(entry[1], entry[2])
        if exists == false then
            local ok, err = pcall(MySQL.query.await, ('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(entry[1], entry[2], entry[3]))
            if not ok then
                print(('^1[XS-Trucking]^0 could not add %s.%s: %s'):format(entry[1], entry[2], tostring(err)))
                return false
            end
            if entry.after then pcall(entry.after) end
        elseif exists == nil then
            print(('^1[XS-Trucking]^0 could not inspect %s.%s, skipped it.'):format(entry[1], entry[2]))
        end
    end

    pcall(migrateTrailers)
    return true
end

function WaitForDB(timeout)
    if DB.ready then return true end
    if DB.failed then return false end

    local waited, limit = 0, timeout or 10000
    while not DB.ready and not DB.failed and waited < limit do
        Wait(50)
        waited = waited + 50
    end
    return DB.ready
end
