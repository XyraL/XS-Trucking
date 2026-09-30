Config = {}

-- Prints what the resource detected and why it refused things. Leave off on a live server.
Config.Debug = false

-- ── Admins ─────────────────────────────────────────────────────────────────
-- /truckingadmin opens the admin panel and /truckingbuilder the builder.
-- Any ONE of these is enough:
--   add_ace group.admin xs.trucking allow        (in server.cfg)
--   a framework permission group listed in groups
--   a license listed in licenses (without the "license:" prefix)
Config.Admin = {
    command = 'truckingadmin',
    builderCommand = 'truckingbuilder',
    acePermission = 'xs.trucking',
    groups = { 'god', 'admin' },
    licenses = {},
}

-- ── Other resources ────────────────────────────────────────────────────────
-- 'auto' finds whatever is running. Set a name to force one.
Config.Bridges = {
    framework = 'auto',   -- 'qbox' or 'qbcore'
    target = 'auto',      -- 'ox_target' or 'qb-target'

    -- Vehicle keys:
    -- 'qbx_vehiclekeys', 'qb-vehiclekeys', 'qs-vehiclekeys', 'wasabi_carlock',
    -- 'Renewed-Vehiclekeys', 'mk_vehiclekeys', 'cd_garage', 'okokGarage',
    -- 't1ger_keys', 'vehicles_keys', 'custom' or 'none'.
    keys = 'auto',

    -- Fuel: 'ox_fuel', 'LegacyFuel', 'cdn-fuel', 'ps-fuel', 'lj-fuel' or 'none'.
    -- Trucks are filled through it when they come out and read back when they
    -- are parked, so owned trucks keep what was left in the tank.
    fuel = 'auto',

    -- Where illegal-run tip-offs go: 'XS-Dispatch', 'ps-dispatch',
    -- 'qs-dispatch', 'cd_dispatch', 'core_dispatch', 'rcore_dispatch',
    -- 'linden_outlawalert' or 'none' (a plain notification and a blip).
    dispatch = 'auto',

    -- Only used when illegal runs pay out an item (Config.Illegal.payout.item):
    -- 'ox_inventory', 'qb-inventory', 'qs-inventory', 'ps-inventory' or 'none'.
    inventory = 'auto',
}

-- Server event fired when keys = 'custom': TriggerEvent(name, source, plate, netId)
Config.CustomKeysEvent = ''

-- 'ox' uses ox_lib notifications, 'framework' uses Qbox/QBCore's own.
Config.Notify = {
    style = 'ox',
    position = 'top-right',
}

-- Account pay goes into, and the money symbol shown in the laptop.
Config.Payout = {
    account = 'bank',
}
Config.Currency = '$'

-- Distances in the laptop: 'mi' or 'km'.
Config.DistanceUnit = 'mi'

-- ── The job ────────────────────────────────────────────────────────────────
Config.Job = {
    -- Put the driver in the cab when the truck comes out.
    warpIntoTruck = true,

    -- Truck plates start with this. The rest is random.
    platePrefix = 'XSTR',

    -- How close the trailer has to be to a drop point, and the truck to a
    -- return point.
    deliverRadius = 10.0,
    returnRadius = 9.0,

    -- Trucks can be brought back to any trucking spot, not only the one they
    -- came from.
    returnAnySpot = true,

    -- A truck bay counts as taken while any vehicle is this close to it.
    bayClearRadius = 4.0,

    -- Dropping a load you have taken. The truck and trailer are taken back.
    cancelFee = 250,

    -- A route with a timer pays this percent when it arrives late.
    latePayPercent = 50,

    -- Seconds between being able to take loads, after cancelling one.
    cancelCooldown = 60,
}

-- ── Trailer types ──────────────────────────────────────────────────────────
-- Every route hauls one of these. The load comes on its trailer: the spot
-- hands it out at a trailer bay, or at the route's own pickup point.
-- `cert` is the certificate a driver needs for it (false for none).
Config.TrailerTypes = {
    { id = 'dryvan',    label = 'Dry van',    models = { 'trailers3', 'trailers', 'trailers4' }, cert = false },
    { id = 'reefer',    label = 'Reefer',     models = { 'trailers2' },                          cert = 'reefer' },
    { id = 'flatbed',   label = 'Flatbed',    models = { 'trflat' },                             cert = 'flatbed' },
    { id = 'logs',      label = 'Logs',       models = { 'trailerlogs' },                        cert = 'flatbed' },
    { id = 'carhauler', label = 'Car hauler', models = { 'tr4' },                                cert = 'carhauler' },
    { id = 'tanker',    label = 'Tanker',     models = { 'tanker', 'tanker2' },                  cert = 'hazmat' },
    { id = 'container', label = 'Container',  models = { 'docktrailer' },                        cert = false },
    { id = 'heavy',     label = 'Heavy haul', models = { 'freighttrailer', 'armytrailer' },      cert = 'oversize' },
}

-- ── Trucks ─────────────────────────────────────────────────────────────────
-- The depot truck is free and always there. Bought trucks pay more on every
-- load and keep their upgrades, paint and wear. Every truck here has to be a
-- tractor unit that can hitch a trailer.
Config.Trucks = {
    depot = { model = 'hauler', label = 'Depot Hauler' },

    shop = {
        { model = 'packer',   label = 'Packer',         price = 15000, bonus = 10, level = 1 },
        { model = 'phantom',  label = 'Phantom',        price = 35000, bonus = 20, level = 6 },
        { model = 'phantom3', label = 'Phantom Custom', price = 65000, bonus = 30, level = 14 },
    },

    -- Owned trailers are optional. Hauling a load on your own trailer of the
    -- same type pays `bonus` percent more.
    trailers = {
        { type = 'dryvan',  model = 'trailers3', label = 'Dry van',   price = 12000, bonus = 6 },
        { type = 'reefer',  model = 'trailers2', label = 'Reefer',    price = 20000, bonus = 8 },
        { type = 'flatbed', model = 'trflat',    label = 'Flatbed',   price = 16000, bonus = 7 },
        { type = 'tanker',  model = 'tanker',    label = 'Tanker',    price = 30000, bonus = 10 },
    },

    -- What a truck can be sold back for, as a percent of what it cost.
    sellBack = 55,
}

-- ── Truck parts ────────────────────────────────────────────────────────────
-- Owned trucks only; the depot truck never wears. `perKm` is percent lost
-- per kilometre, `perDamage` extra per point of body and engine damage.
-- `cost` is a full replacement; part services cost what is worn of it.
Config.Parts = {
    enabled = true,
    list = {
        { id = 'engine', label = 'Engine', perKm = 0.30, perDamage = 0.004, cost = 4200 },
        { id = 'tyres',  label = 'Tyres',  perKm = 0.85, perDamage = 0.004, cost = 1800 },
        { id = 'brakes', label = 'Brakes', perKm = 0.60, perDamage = 0.005, cost = 1400 },
        { id = 'oil',    label = 'Oil',    perKm = 0.45, perDamage = 0.001, cost = 900 },
    },
    -- Body condition drops with damage taken on a run. Repair cost per point.
    bodyLossPerDamage = 0.05,
    bodyCostPerPoint = 15,

    -- What a worn part does on the road.
    tyresGripBelow = 25,
    brakesDamageBelow = 25,
    brakesDamageMult = 1.6,
    oilEngineDrainBelow = 20,
    enginePowerBelow = 30,
    warnBelow = 25,
}

-- Filling up at a trucking spot's laptop, per percent of the tank.
Config.DepotFuelPrice = 22

-- ── Upgrades ───────────────────────────────────────────────────────────────
-- Bought per owned truck in the Truck page. Performance levels cost
-- `cost` times the level being bought.
Config.Upgrades = {
    performance = {
        { id = 'engine',       label = 'Engine tune',  mod = 11, levels = 4, cost = 3000 },
        { id = 'transmission', label = 'Transmission', mod = 13, levels = 3, cost = 2500 },
        { id = 'brakes',       label = 'Brakes',       mod = 12, levels = 3, cost = 2000 },
        { id = 'suspension',   label = 'Suspension',   mod = 15, levels = 4, cost = 2200 },
        { id = 'turbo',        label = 'Turbo',        toggle = 18, levels = 1, cost = 9000 },
    },

    paint = {
        cost = 2500,
        colours = {
            { id = 0,   label = 'Black',        hex = '#0d0e10' },
            { id = 1,   label = 'Graphite',     hex = '#2a2c30' },
            { id = 4,   label = 'Silver',       hex = '#9aa0a8' },
            { id = 111, label = 'Frost white',  hex = '#eef0f2' },
            { id = 27,  label = 'Red',          hex = '#b3121b' },
            { id = 38,  label = 'Orange',       hex = '#e8611a' },
            { id = 89,  label = 'Race yellow',  hex = '#f2c300' },
            { id = 53,  label = 'Green',        hex = '#1d6b3a' },
            { id = 64,  label = 'Blue',         hex = '#1d3f8f' },
            { id = 70,  label = 'Bright blue',  hex = '#2e8fd6' },
            { id = 145, label = 'Purple',       hex = '#4b2a7a' },
            { id = 135, label = 'Hot pink',     hex = '#e83e8c' },
        },
    },

    lights = { cost = 3500 },   -- xenon headlights, with a colour pick
    tint = { cost = 1200 },     -- window tint, three shades
    horns = { cost = 1500, list = { 'Truck horn', 'Cop horn', 'Clown horn', 'Musical 1', 'Musical 2', 'Musical 3' } },
}

-- ── Levels ─────────────────────────────────────────────────────────────────
-- Total XP to reach level n is base × (n - 1) ^ exponent. With the defaults a
-- normal load is about 100 XP, level 10 takes around 45 loads and level 50
-- around 600. Every level gives skill points to spend in the skill tree.
Config.Levels = {
    max = 50,
    base = 150,
    exponent = 1.55,
    skillPointsPerLevel = 1,

    -- The title shown from each level on.
    titles = {
        [1] = 'Rookie Hauler',
        [3] = 'Regional Driver',
        [6] = 'Long-Haul Trucker',
        [10] = 'Road Captain',
        [15] = 'Owner-Operator',
        [20] = 'Freight Veteran',
        [30] = 'Highway Legend',
        [40] = 'King of the Road',
        [50] = 'Master Trucker',
    },
}

-- ── Certificates ───────────────────────────────────────────────────────────
-- Earned in the laptop once a driver has the level and deliveries, for the
-- fee. Trailer types above and single routes can require one.
Config.Certificates = {
    { id = 'reefer',    label = 'Refrigerated Freight', level = 2,  deliveries = 5,  fee = 2500,
      description = 'Reefer trailers. Food and medical loads that have to arrive on time.' },
    { id = 'flatbed',   label = 'Flatbed & Timber',     level = 4,  deliveries = 15, fee = 5000,
      description = 'Flatbeds and log trailers. Construction materials and timber.' },
    { id = 'carhauler', label = 'Car Hauler',           level = 8,  deliveries = 30, fee = 9000,
      description = 'Car carriers. Dealership stock and auction lots.' },
    { id = 'hazmat',    label = 'Hazmat & Tanker',      level = 12, deliveries = 50, fee = 15000,
      description = 'Tankers. Fuel and chemicals, with the pay to match.' },
    { id = 'oversize',  label = 'Oversize Loads',       level = 16, deliveries = 80, fee = 25000,
      description = 'Heavy haul. Transformers and machinery, usually with an escort.' },
}

-- ── Skill tree ─────────────────────────────────────────────────────────────
-- Five branches. Each skill has ranks bought with skill points; `requires`
-- lists skills that need at least one rank first. Effects apply per rank:
--   pay       percent more pay        (when: minKm, minWeight, night, types, illegal, business, oversize)
--   xp        percent more XP
--   wear      percent less part wear
--   repair    percent off repairs and services
--   upgrade   percent off upgrades
--   rating    percent less rating lost to damage
--   dock      percent bonus for a clean reverse into the drop point
--   timer     percent more time on timed loads
--   convoy    extra convoy bonus percent
--   escort    percent more escort pay
--   cut       percent more of a business load's pay to the driver
--   rep       percent more business reputation
--   tipoff    percent lower tip-off chance on illegal runs
--   heatDecay percent faster heat decay
--   heatGain  percent less heat per illegal run
Config.Skills = {
    respecCost = 5000,

    branches = {
        {
            id = 'longhaul', label = 'Long Haul', colour = '#38d9ff',
            skills = {
                { id = 'lh_miles', label = 'Mile Muncher', ranks = 3,
                  description = 'More pay on loads of 6 km and over.',
                  effects = { { stat = 'pay', value = 3, when = { minKm = 6 } } } },
                { id = 'lh_night', label = 'Night Shift', ranks = 1, requires = { 'lh_miles' },
                  description = 'More pay on loads taken between 21:00 and 05:00.',
                  effects = { { stat = 'pay', value = 8, when = { night = true } } } },
                { id = 'lh_pedal', label = 'Pedal Down', ranks = 2, requires = { 'lh_miles' },
                  description = 'More time on timed loads.',
                  effects = { { stat = 'timer', value = 10 } } },
                { id = 'lh_scholar', label = 'Road Scholar', ranks = 2, requires = { 'lh_night' },
                  description = 'More XP from every load.',
                  effects = { { stat = 'xp', value = 5 } } },
                { id = 'lh_king', label = 'King of the Road', ranks = 1, requires = { 'lh_scholar', 'lh_pedal' },
                  description = 'A big bonus on loads of 12 km and over.',
                  effects = { { stat = 'pay', value = 10, when = { minKm = 12 } } } },
            },
        },
        {
            id = 'precision', label = 'Precision', colour = '#3fe08f',
            skills = {
                { id = 'pr_smooth', label = 'Smooth Operator', ranks = 2,
                  description = 'Lose less rating to damage.',
                  effects = { { stat = 'rating', value = 15 } } },
                { id = 'pr_dock', label = 'Dock Master', ranks = 2, requires = { 'pr_smooth' },
                  description = 'A bonus for backing the trailer neatly into the drop point.',
                  effects = { { stat = 'dock', value = 4 } } },
                { id = 'pr_care', label = 'Mechanical Sympathy', ranks = 2,
                  description = 'Parts wear slower on your own trucks.',
                  effects = { { stat = 'wear', value = 12 } } },
                { id = 'pr_perfect', label = 'Perfect Record', ranks = 1, requires = { 'pr_dock', 'pr_care' },
                  description = 'More pay on every load while your rating is 90 or better.',
                  effects = { { stat = 'pay', value = 6, when = { minRating = 90 } } } },
            },
        },
        {
            id = 'heavy', label = 'Heavy Haul', colour = '#ffb547',
            skills = {
                { id = 'hh_lifter', label = 'Heavy Lifter', ranks = 3,
                  description = 'More pay on loads of 20 tonnes and over.',
                  effects = { { stat = 'pay', value = 4, when = { minWeight = 20 } } } },
                { id = 'hh_convoy', label = 'Convoy Captain', ranks = 2, requires = { 'hh_lifter' },
                  description = 'A bigger convoy bonus.',
                  effects = { { stat = 'convoy', value = 5 } } },
                { id = 'hh_pilot', label = 'Pilot Car Pro', ranks = 2,
                  description = 'More pay when you escort an oversize load.',
                  effects = { { stat = 'escort', value = 10 } } },
                { id = 'hh_titan', label = 'Titan', ranks = 1, requires = { 'hh_convoy' },
                  description = 'A big bonus on heavy haul loads.',
                  effects = { { stat = 'pay', value = 10, when = { types = { 'heavy' } } } } },
            },
        },
        {
            id = 'business', label = 'Business', colour = '#8f7dff',
            skills = {
                { id = 'bz_negotiator', label = 'Negotiator', ranks = 3,
                  description = 'Keep more of the pay when you drive a business truck.',
                  effects = { { stat = 'cut', value = 3 } } },
                { id = 'bz_mechanic', label = 'Fleet Mechanic', ranks = 2,
                  description = 'Cheaper repairs and services.',
                  effects = { { stat = 'repair', value = 10 } } },
                { id = 'bz_tuner', label = 'Tuner', ranks = 2, requires = { 'bz_mechanic' },
                  description = 'Cheaper upgrades.',
                  effects = { { stat = 'upgrade', value = 8 } } },
                { id = 'bz_ambassador', label = 'Brand Ambassador', ranks = 2,
                  description = 'Your loads earn your business more reputation.',
                  effects = { { stat = 'rep', value = 10 } } },
                { id = 'bz_tycoon', label = 'Tycoon', ranks = 1, requires = { 'bz_negotiator', 'bz_ambassador' },
                  description = 'More pay on every load hauled with a business truck.',
                  effects = { { stat = 'pay', value = 5, when = { business = true } } } },
            },
        },
        {
            id = 'smuggler', label = 'Smuggler', colour = '#ff5d6c',
            skills = {
                { id = 'sm_low', label = 'Low Profile', ranks = 3,
                  description = 'Illegal runs are less likely to be reported.',
                  effects = { { stat = 'tipoff', value = 10 } } },
                { id = 'sm_cool', label = 'Cool Head', ranks = 2,
                  description = 'Heat fades faster.',
                  effects = { { stat = 'heatDecay', value = 25 } } },
                { id = 'sm_connections', label = 'Connections', ranks = 2, requires = { 'sm_low' },
                  description = 'Illegal runs pay more.',
                  effects = { { stat = 'pay', value = 8, when = { illegal = true } } } },
                { id = 'sm_ghost', label = 'Ghost', ranks = 1, requires = { 'sm_connections', 'sm_cool' },
                  description = 'Much less heat per run, and even fewer tip-offs.',
                  effects = { { stat = 'heatGain', value = 50 }, { stat = 'tipoff', value = 15 } } },
            },
        },
    },
}

-- ── Pay ────────────────────────────────────────────────────────────────────
Config.Pay = {
    -- The route builder suggests pay from the route's length: base plus
    -- perKm for every kilometre, times the trailer type's multiplier.
    suggest = {
        base = 150,
        perKm = 110,
        xpPerKm = 14,
        types = { dryvan = 1.0, reefer = 1.2, flatbed = 1.25, logs = 1.25, carhauler = 1.4, tanker = 1.6, container = 1.1, heavy = 1.9 },
    },

    -- Two stops or more.
    multiStopBonus = 25,

    -- Driving rating: a running average of how clean each run was.
    rating = {
        damagePerPoint = 20,   -- body and engine damage per rating point lost on a run
        bonusAt = 90, bonus = 5,
        penaltyAt = 50, penalty = 5,
    },

    -- Hot loads: a few routes at a time pay a bonus, swapped every rotateMinutes.
    hot = { enabled = true, count = 2, rotateMinutes = 30, bonus = 50 },

    -- A clean reverse into the drop point (Dock Master) is judged on how
    -- close the trailer is to the point and how straight it sits.
    dock = { maxDistance = 3.0, maxAngle = 12.0 },
}

-- ── Co-op ──────────────────────────────────────────────────────────────────
Config.Coop = {
    -- Convoys: several trucks take one route together. Everyone hauls their
    -- own trailer and gets bonusPerTruck percent for every other truck, as
    -- long as they all deliver within windowMinutes of the first.
    convoy = { enabled = true, maxTrucks = 4, bonusPerTruck = 10, maxBonus = 30, windowMinutes = 3 },

    -- Escorts: routes marked for an escort need a player in a pilot car
    -- close to the load for most of the trip. The escort is paid cut percent
    -- of the load on top, the driver loses nothing.
    escort = {
        enabled = true,
        vehicle = 'sadler',     -- the pilot car handed out; escorts can also bring their own
        cut = 25,
        range = 150.0,          -- metres from the load
        presence = 70,          -- percent of the trip they have to be in range
    },

    -- Co-drivers ride in the cab and are paid cut percent of the load on top.
    codriver = { enabled = true, cut = 35, xp = 60 },
}

-- ── Illegal runs ───────────────────────────────────────────────────────────
Config.Illegal = {
    enabled = true,
    level = 5,                 -- level needed before illegal loads show up

    -- Chance, in percent, that someone reports the run to the police. Heat
    -- adds heatChance percent for every point of heat the driver has.
    tipChance = 20,
    heatChance = 0.5,
    maxChance = 90,

    heatPerRun = 20,
    maxHeat = 100,
    blockAt = 100,             -- heat at which a driver cannot take illegal loads
    decayPerHour = 10,

    -- Paid in cash by default. Set item to e.g. 'black_money' to pay an item
    -- instead, through the inventory bridge.
    payout = { account = 'cash', item = false },

    policeJobs = { 'police', 'sheriff', 'bcso', 'sasp', 'lspd', 'state' },
    alert = {
        code = '10-66',
        title = 'Suspicious Cargo',
        description = 'A caller reports a truck hauling what looks like smuggled cargo.',
        sprite = 477,
        colour = 1,
        seconds = 300,
    },
}

-- ── Businesses ─────────────────────────────────────────────────────────────
Config.Business = {
    enabled = true,
    foundingCost = 25000,
    nameLength = { 3, 32 },

    -- Logos are pictures from these hosts only, over https.
    logoHosts = { 'imgur.com', 'fivemanage.com' },

    -- Members and business trucks allowed, and what buying more costs.
    members = { base = 6, upgrades = { { add = 4, cost = 15000 }, { add = 6, cost = 40000 }, { add = 10, cost = 90000 } } },
    fleet = { base = 3, upgrades = { { add = 3, cost = 20000 }, { add = 5, cost = 60000 }, { add = 8, cost = 120000 } } },

    -- What each permission lets a rank do.
    permissions = {
        invite = 'Invite players',
        kick = 'Remove members',
        promote = 'Change member ranks',
        ranks = 'Edit ranks and pay',
        bank = 'Withdraw from the bank',
        fleet = 'Buy, sell and look after trucks',
        perks = 'Spend perk points and buy upgrades',
        settings = 'Change the name, logo and colours',
    },

    -- The ranks a new business starts with. `cut` is the percent of a load's
    -- pay the driver keeps when they haul with a business truck; the rest
    -- goes to the business bank. Loads on your own truck pay you in full.
    ranks = {
        { name = 'Driver',     cut = 60, permissions = {} },
        { name = 'Dispatcher', cut = 70, permissions = { 'invite', 'fleet' } },
        { name = 'Manager',    cut = 75, permissions = { 'invite', 'kick', 'promote', 'fleet', 'perks' } },
        { name = 'Owner',      cut = 85, permissions = '*' },
    },
    maxRanks = 8,

    -- Reputation levels. Each new level gives perk points.
    levels = {
        { level = 1, rep = 0,     title = 'Startup Carrier',  points = 0 },
        { level = 2, rep = 500,   title = 'Local Carrier',    points = 1 },
        { level = 3, rep = 1500,  title = 'Regional Carrier', points = 1 },
        { level = 4, rep = 3500,  title = 'National Freight', points = 2 },
        { level = 5, rep = 7000,  title = 'Logistics Group',  points = 2 },
        { level = 6, rep = 12000, title = 'Freight Empire',   points = 3 },
    },
    repPerLoad = 15,

    -- Perks, bought with perk points. Each tier needs the one before it.
    perks = {
        {
            id = 'fleet', label = 'Fleet',
            tiers = {
                { id = 'fleet_1', label = 'Extra Bay',     cost = 1, description = 'Send one more truck out on fleet runs.', runs = 1 },
                { id = 'fleet_2', label = 'Big Yard',      cost = 2, description = 'Send two more trucks out on fleet runs.', runs = 2 },
                { id = 'fleet_3', label = 'Service Deal',  cost = 2, description = 'Business trucks cost 15% less to repair.', repair = 15 },
            },
        },
        {
            id = 'logistics', label = 'Logistics',
            tiers = {
                { id = 'logistics_1', label = 'Route Planning', cost = 1, description = 'Fleet runs finish 15% sooner.', runTime = 15 },
                { id = 'logistics_2', label = 'Better Rates',   cost = 2, description = 'Every member earns 5% more on business trucks.', pay = 5 },
                { id = 'logistics_3', label = 'Priority Freight', cost = 3, description = 'Every member earns another 5%.', pay = 5 },
            },
        },
        {
            id = 'treasury', label = 'Treasury',
            tiers = {
                { id = 'treasury_1', label = 'Smart Banking',   cost = 1, description = 'Deposits get 5% added.', deposit = 5 },
                { id = 'treasury_2', label = 'Investment Fund', cost = 2, description = 'Deposits get another 10%.', deposit = 10 },
            },
        },
        {
            id = 'brand', label = 'Brand',
            tiers = {
                { id = 'brand_1', label = 'Known Name',   cost = 1, description = '20% more reputation from every load.', rep = 20 },
                { id = 'brand_2', label = 'Trusted Name', cost = 2, description = 'Another 20% reputation.', rep = 20 },
            },
        },
    },

    -- Fleet runs: an idle truck is sent to haul a route on its own. It pays
    -- payPercent of the route and is back after minutes.
    runs = { enabled = true, payPercent = 50, minutes = 20, max = 3 },

    ledgerLimit = 60,
}

-- ── Leaderboards ───────────────────────────────────────────────────────────
Config.Leaderboards = {
    limit = 15,
}

-- ── The default trucking spot ──────────────────────────────────────────────
-- Created once, the first time the resource starts with no spots in the
-- database. Edit it, or add more, in /truckingbuilder.
Config.DefaultSpot = {
    name = 'Port of Los Santos',
    blip = { sprite = 477, colour = 5, scale = 0.8 },
    -- The laptop sits on a computer already in the map, so no prop is spawned.
    laptop = { x = 1209.09, y = -3114.97, z = 5.61, h = 75.18, prop = false },
    truckBays = {
        { x = 1244.4124, y = -3135.5105, z = 5.8264, h = 270.9522 },
        { x = 1243.7046, y = -3142.3057, z = 5.8056, h = 271.0386 },
        { x = 1244.1990, y = -3149.2036, z = 5.8209, h = 270.3443 },
        { x = 1244.2622, y = -3155.7896, z = 5.8229, h = 270.6933 },
    },
    trailerBays = {
        { x = 1273.9138, y = -3160.4355, z = 6.1377, h = 90.7130 },
        { x = 1273.3838, y = -3168.9919, z = 6.1392, h = 90.3086 },
        { x = 1272.8040, y = -3174.9897, z = 6.1591, h = 89.2655 },
        { x = 1272.3174, y = -3184.5920, z = 6.1424, h = 86.1031 },
    },
    returns = {},
}

-- Routes created with the default spot.
Config.DefaultRoutes = {
    { label = 'General Freight', cargo = 'Consumer goods', type = 'dryvan', weight = 12, pay = 350, xp = 40, level = 1,
      stops = { { x = -509.84, y = -2852.44, z = 5.24, h = 45.51 } } },
    { label = 'Airport Cargo', cargo = 'Air freight', type = 'dryvan', weight = 10, pay = 400, xp = 45, level = 1,
      stops = { { x = -979.5997, y = -2865.0774, z = 14.1832, h = 59.9426 } } },
    { label = 'Regional Multi-Drop', cargo = 'Mixed freight', type = 'dryvan', weight = 14, pay = 500, xp = 90, level = 3,
      stops = { { x = -509.84, y = -2852.44, z = 5.24, h = 45.51 }, { x = -979.5997, y = -2865.0774, z = 14.1832, h = 59.9426 } } },
    { label = 'Studio Catering', cargo = 'Chilled food', type = 'reefer', weight = 14, pay = 650, xp = 70, level = 2, timer = 480,
      stops = { { x = -1025.7351, y = -516.4412, z = 36.4587, h = 25.0652 } } },
    { label = 'Vinewood Build', cargo = 'Steel beams', type = 'flatbed', weight = 22, pay = 900, xp = 100, level = 4,
      convoy = { min = 1, max = 3 },
      stops = { { x = 457.0935, y = 224.7394, z = 103.3604, h = 339.5320 } } },
    { label = 'Hillside Transformer', cargo = 'Power transformer', type = 'heavy', weight = 62, pay = 2600, xp = 260, level = 16,
      escorts = 1,
      stops = { { x = 457.0935, y = 224.7394, z = 103.3604, h = 339.5320 } } },
    { label = 'No Questions Asked', cargo = 'Sealed container', type = 'container', weight = 18, pay = 1800, xp = 120, level = 5,
      illegal = true,
      pickup = { x = -509.84, y = -2852.44, z = 5.24, h = 45.51 },
      stops = { { x = -979.5997, y = -2865.0774, z = 14.1832, h = 59.9426 } } },
}
