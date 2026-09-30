Target = { name = nil }

if IsDuplicityVersion() then return end

do
    local forced = Config.Bridges.target
    if forced ~= 'auto' then
        Target.name = forced ~= 'none' and forced or nil
    elseif GetResourceState('ox_target') == 'started' then
        Target.name = 'ox_target'
    elseif GetResourceState('qb-target') == 'started' then
        Target.name = 'qb-target'
    end

    if not Target.name then
        print('^1[XS-Trucking]^0 No target resource found. Start ox_target or qb-target before XS-Trucking.')
    end
end

local registered = {}

local function oxOptions(id, options)
    local built = {}
    for _, option in ipairs(options) do
        built[#built + 1] = {
            name = ('%s:%s'):format(id, option.id),
            label = option.label,
            icon = option.icon,
            distance = option.distance or 2.5,
            canInteract = option.canInteract,
            onSelect = option.action,
        }
    end
    return built
end

local function qbOptions(options)
    local built = {}
    for _, option in ipairs(options) do
        built[#built + 1] = {
            label = option.label,
            icon = option.icon,
            action = option.action,
            canInteract = option.canInteract,
        }
    end
    return built
end

function Target.AddSphere(id, coords, radius, options)
    Target.Remove(id)

    if Target.name == 'ox_target' then
        registered[id] = { zone = exports.ox_target:addSphereZone({
            coords = vec3(coords.x, coords.y, coords.z),
            radius = radius,
            debug = Config.Debug,
            options = oxOptions(id, options),
        }) }
    elseif Target.name == 'qb-target' then
        exports['qb-target']:AddCircleZone(id, vec3(coords.x, coords.y, coords.z), radius, {
            name = id, debugPoly = Config.Debug, useZ = true,
        }, { options = qbOptions(options), distance = 2.5 })
        registered[id] = { named = id }
    end
end

function Target.AddEntity(id, entity, options)
    if not entity or entity == 0 then return end
    Target.Remove(id)

    if Target.name == 'ox_target' then
        exports.ox_target:addLocalEntity(entity, oxOptions(id, options))
        registered[id] = { entity = entity }
    elseif Target.name == 'qb-target' then
        exports['qb-target']:AddTargetEntity(entity, { options = qbOptions(options), distance = 3.0 })
        registered[id] = { entity = entity }
    end
end

function Target.AddPlayers(id, options)
    if registered[id] then return end

    if Target.name == 'ox_target' then
        exports.ox_target:addGlobalPlayer(oxOptions(id, options))
        registered[id] = { players = true, names = (function()
            local names = {}
            for _, option in ipairs(options) do names[#names + 1] = ('%s:%s'):format(id, option.id) end
            return names
        end)() }
    elseif Target.name == 'qb-target' then
        exports['qb-target']:AddGlobalPlayer({ options = qbOptions(options), distance = 3.0 })
        local labels = {}
        for _, option in ipairs(options) do labels[#labels + 1] = option.label end
        registered[id] = { players = true, labels = labels }
    end
end

function Target.Remove(id)
    local entry = registered[id]
    if not entry then return end
    registered[id] = nil

    pcall(function()
        if Target.name == 'ox_target' then
            if entry.entity then exports.ox_target:removeLocalEntity(entry.entity)
            elseif entry.zone then exports.ox_target:removeZone(entry.zone)
            elseif entry.players then exports.ox_target:removeGlobalPlayer(entry.names) end
        elseif Target.name == 'qb-target' then
            if entry.entity then exports['qb-target']:RemoveTargetEntity(entry.entity)
            elseif entry.named then exports['qb-target']:RemoveZone(entry.named)
            elseif entry.players then exports['qb-target']:RemoveGlobalPlayer(entry.labels) end
        end
    end)
end

function Target.Clear(prefix)
    for id in pairs(registered) do
        if id:sub(1, #prefix) == prefix then Target.Remove(id) end
    end
end
