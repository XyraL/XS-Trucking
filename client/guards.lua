local GUARDS = joaat('XS_TRUCKING_GUARDS')
local PLAYERS = joaat('PLAYER')

local known, armed = {}, {}
local warned = nil

AddRelationshipGroup('XS_TRUCKING_GUARDS')
SetRelationshipBetweenGroups(5, GUARDS, PLAYERS)
SetRelationshipBetweenGroups(5, PLAYERS, GUARDS)
SetRelationshipBetweenGroups(0, GUARDS, GUARDS)

local function guardData(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) or not NetworkGetEntityIsNetworked(entity) then return nil end
    return Entity(entity).state.xsGuard
end

AddStateBagChangeHandler('xsGuard', nil, function(bagName, _, value)
    local netId = tonumber(bagName:match('^entity:(%d+)$'))
    if not netId then return end
    known[netId] = value or nil
    if not value then armed[netId] = nil end
end)

local function arm(ped, data)
    SetPedRelationshipGroupHash(ped, GUARDS)
    SetPedAccuracy(ped, data.accuracy or 40)
    SetPedCombatAbility(ped, 2)
    SetPedCombatMovement(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedCombatAttributes(ped, 0, true)
    SetPedCombatAttributes(ped, 46, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedSeeingRange(ped, 90.0)
    SetPedHearingRange(ped, 90.0)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedKeepTask(ped, true)
    TaskGuardCurrentPosition(ped, 10.0, 10.0, true)
end

CreateThread(function()
    while true do
        Wait(next(known) and 500 or 2000)
        for netId in pairs(known) do
            local ped = NetworkDoesNetworkIdExist(netId) and NetworkGetEntityFromNetworkId(netId) or 0
            local data = guardData(ped)
            if not data then
                if ped ~= 0 then known[netId] = nil end
                armed[netId] = nil
            elseif NetworkHasControlOfEntity(ped) then
                if armed[netId] ~= ped and not IsPedDeadOrDying(ped, true) then
                    arm(ped, data)
                    armed[netId] = ped
                end
            else
                armed[netId] = nil
            end
        end
    end
end)

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local state = Run.state
    if not state or not state.guarded or warned == state.id then return end

    local victim, attacker = args[1], args[2]
    if victim ~= cache.ped and attacker ~= cache.ped then return end
    if not guardData(victim) and not guardData(attacker) then return end

    warned = state.id
    TriggerServerEvent('XS-Trucking:server:guardsAlarm')
end)
