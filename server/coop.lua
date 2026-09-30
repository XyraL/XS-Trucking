Coop = { lobbies = {} }

local seq = 0
local rideInvites = {}

local function lobbyOf(src)
    for id, lobby in pairs(Coop.lobbies) do
        if lobby.members[src] then return lobby, id end
    end
    return nil
end

local function counts(lobby)
    local drivers, escorts = 0, 0
    for _, member in pairs(lobby.members) do
        if member.role == 'driver' then drivers = drivers + 1 else escorts = escorts + 1 end
    end
    return drivers, escorts
end

local function limits(route)
    local maxDrivers = route.convoy and route.convoy.max or 1
    local minDrivers = route.convoy and math.max(1, route.convoy.min or 1) or 1
    local escorts = Config.Coop.escort.enabled and (route.escorts or 0) or 0
    return minDrivers, maxDrivers, escorts
end

local function public(lobby, viewer)
    local route = Spots.Route(lobby.route)
    if not route then return nil end
    local minDrivers, maxDrivers, escorts = limits(route)
    local drivers, joinedEscorts = counts(lobby)

    local members = {}
    for src, member in pairs(lobby.members) do
        members[#members + 1] = { source = src, name = member.name, role = member.role, lead = src == lobby.lead, me = src == viewer }
    end
    table.sort(members, function(a, b)
        if a.lead ~= b.lead then return a.lead end
        if a.role ~= b.role then return a.role == 'driver' end
        return a.source < b.source
    end)

    local needEscorts = Config.Coop.escort.required and not route.guards and escorts or 0
    return {
        id = lobby.id, route = lobby.route, spot = lobby.spot, lead = lobby.lead, leadName = lobby.members[lobby.lead] and lobby.members[lobby.lead].name or '',
        members = members, drivers = drivers, maxDrivers = maxDrivers, minDrivers = minDrivers,
        escorts = joinedEscorts, maxEscorts = escorts, needEscorts = needEscorts,
        ready = drivers >= minDrivers and joinedEscorts >= needEscorts,
        mine = viewer and lobby.members[viewer] ~= nil or false,
        expiresIn = math.max(0, lobby.expires - os.time()),
    }
end

function Coop.InCrew(src)
    return lobbyOf(src) ~= nil
end

function Coop.ForSpot(spotId, viewer)
    local out = {}
    for _, lobby in pairs(Coop.lobbies) do
        if lobby.spot == spotId then
            local view = public(lobby, viewer)
            if view then out[#out + 1] = view end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function notifyMembers(lobby, message, except)
    for src in pairs(lobby.members) do
        if src ~= except then Framework.Notify(src, message, 'inform') end
    end
end

local function refresh(lobby)
    for src in pairs(lobby.members) do
        TriggerClientEvent('XS-Trucking:client:crew', src, public(lobby, src))
    end
end

local function close(lobby, message, except)
    Coop.lobbies[lobby.id] = nil
    for src in pairs(lobby.members) do
        TriggerClientEvent('XS-Trucking:client:crew', src, false)
        if message and src ~= except then Framework.Notify(src, message, 'inform') end
    end
end

function Coop.Open(src, spotId, routeId)
    if lobbyOf(src) then return false, 'You are already in a crew.' end

    local ok, data = Jobs.Validate(src, spotId, routeId)
    if not ok then return false, data end

    local route = data.route
    local _, maxDrivers, escorts = limits(route)
    if maxDrivers < 2 and escorts < 1 then return false, 'This load is for one truck. Take it on your own.' end

    local locked = Jobs.LockReason(route, Progress.Profile(src), data.cid)
    if locked then return false, ('Locked: %s.'):format(locked) end

    seq = seq + 1
    local lobby = {
        id = seq, spot = data.spot.id, route = route.id, lead = src,
        members = { [src] = { role = 'driver', name = Framework.GetName(src) } },
        expires = os.time() + (Config.Coop.lobbyMinutes or 10) * 60,
    }
    Coop.lobbies[seq] = lobby
    refresh(lobby)
    return true, public(lobby, src)
end

function Coop.Join(src, lobbyId, role)
    lobbyId = tonumber(lobbyId)
    local lobby = lobbyId and Coop.lobbies[lobbyId]
    if not lobby then return false, 'That crew has gone.' end
    if lobbyOf(src) then return false, 'You are already in a crew.' end
    role = role == 'escort' and 'escort' or 'driver'

    local ok, data = Jobs.Validate(src, lobby.spot, lobby.route)
    if not ok then return false, data end

    local _, maxDrivers, maxEscorts = limits(data.route)
    local drivers, escorts = counts(lobby)

    if role == 'driver' then
        if drivers >= maxDrivers then return false, 'Every truck in this convoy is taken.' end
        local locked = Jobs.LockReason(data.route, Progress.Profile(src), data.cid)
        if locked then return false, ('You cannot haul this one yet: %s.'):format(locked) end
    else
        if escorts >= maxEscorts then return false, 'This load has all the escorts it needs.' end
    end

    lobby.members[src] = { role = role, name = Framework.GetName(src) }
    notifyMembers(lobby, ('%s joined the crew as %s.'):format(lobby.members[src].name, role == 'driver' and 'a driver' or 'an escort'), src)
    refresh(lobby)
    return true, public(lobby, src)
end

function Coop.Leave(src)
    local lobby = lobbyOf(src)
    if not lobby then return false, 'You are not in a crew.' end

    if lobby.lead == src then
        close(lobby, 'The crew was called off.', src)
        return true
    end

    local name = lobby.members[src].name
    lobby.members[src] = nil
    TriggerClientEvent('XS-Trucking:client:crew', src, false)
    notifyMembers(lobby, ('%s left the crew.'):format(name))
    refresh(lobby)
    return true
end

function Coop.Kick(src, target)
    local lobby = lobbyOf(src)
    target = tonumber(target)
    if not lobby or lobby.lead ~= src then return false, 'Only the crew lead can do that.' end
    if not target or target == src or not lobby.members[target] then return false, 'They are not in your crew.' end

    lobby.members[target] = nil
    TriggerClientEvent('XS-Trucking:client:crew', target, false)
    Framework.Notify(target, 'You were taken off the crew.', 'inform')
    refresh(lobby)
    return true
end

function Coop.Start(src, hour)
    local lobby = lobbyOf(src)
    if not lobby then return false, 'You are not in a crew.' end
    if lobby.lead ~= src then return false, 'Only the crew lead can roll out.' end

    local view = public(lobby, src)
    if not view then
        close(lobby)
        return false, 'That load is gone.'
    end
    if view.drivers < view.minDrivers then return false, ('This convoy needs %d trucks.'):format(view.minDrivers) end
    if view.escorts < view.needEscorts then
        return false, ('This load needs %d escort%s first.'):format(view.needEscorts, view.needEscorts == 1 and '' or 's')
    end

    lobby.hour = tonumber(hour)
    local ok, err = Jobs.StartCrew(lobby)
    if not ok then return false, err end

    Coop.lobbies[lobby.id] = nil
    for member in pairs(lobby.members) do
        TriggerClientEvent('XS-Trucking:client:crew', member, false)
        TriggerClientEvent('XS-Trucking:client:closeUI', member)
    end
    return true
end

function Coop.InviteRider(src, target)
    if not Config.Coop.codriver.enabled then return false, 'Co-drivers are turned off.' end
    target = tonumber(target)

    local job = Jobs.active[src]
    if not job or job.role ~= 'driver' then return false, 'You need to be on a load.' end
    if job.codriver then return false, 'You already have a co-driver.' end
    if not target or target == src or not GetPlayerName(target) then return false, 'That player is not around.' end
    if Jobs.Busy(target) then return false, 'They are on a load of their own.' end
    if lobbyOf(target) then return false, 'They are in a crew.' end

    local a, b = GetEntityCoords(GetPlayerPed(src)), GetEntityCoords(GetPlayerPed(target))
    if #(a - b) > 10.0 then return false, 'Stand next to them.' end

    rideInvites[target] = { driver = src, expires = os.time() + 60 }
    TriggerClientEvent('XS-Trucking:client:rideInvite', target, { from = Framework.GetName(src), load = job.route.label })
    return true
end

function Coop.AcceptRide(src)
    local invite = rideInvites[src]
    rideInvites[src] = nil
    if not invite or invite.expires < os.time() then return false, 'That invite has run out.' end
    if lobbyOf(src) then return false, 'Leave your crew first.' end
    return Jobs.AddRider(invite.driver, src)
end

CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for _, lobby in pairs(Coop.lobbies) do
            local route = Spots.Route(lobby.route)
            if lobby.expires < now then
                close(lobby, 'Your crew waited too long and was closed.')
            elseif not route or not route.enabled then
                close(lobby, 'That load was taken off the board, so the crew was closed.')
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    rideInvites[src] = nil
    local lobby = lobbyOf(src)
    if not lobby then return end
    if lobby.lead == src then
        close(lobby, 'The crew lead left, so the crew was closed.')
    else
        lobby.members[src] = nil
        refresh(lobby)
    end
end)
